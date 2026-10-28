#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <deque>
#include <dlfcn.h>
#include <fstream>
#include <iconv.h>
#include <mutex>
#include <poll.h>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#include "bon-api.h"
#include "receiver-client.h"

namespace {

constexpr size_t chunk_size = 188 * 256;
constexpr size_t queue_size = 128;
constexpr DWORD unset_channel = UINT32_MAX;
constexpr DWORD wait_timeout = 0x102;
constexpr DWORD wait_abandoned = 0x80;

std::string trim(const std::string &value)
{
    const auto begin = value.find_first_not_of(" \t\r\n");
    return begin == std::string::npos ? "" : value.substr(begin, value.find_last_not_of(" \t\r\n") - begin + 1);
}

std::u16string utf16(const std::string &value)
{
    std::u16string output(value.size() + 1, u'\0');
    iconv_t converter = iconv_open(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__ ? "UTF-16LE" : "UTF-16BE", "UTF-8");
    if (converter == (iconv_t)-1)
        throw std::runtime_error("cannot initialize UTF-16 conversion");
    char *input = const_cast<char *>(value.data());
    char *destination = reinterpret_cast<char *>(output.data());
    size_t remaining = value.size(), capacity = output.size() * sizeof(char16_t);
    const size_t size = capacity;
    const auto result = iconv(converter, &input, &remaining, &destination, &capacity);
    iconv_close(converter);
    if (result == static_cast<size_t>(-1))
        throw std::runtime_error("invalid UTF-8 tuner or channel name");
    output.resize((size - capacity) / sizeof(char16_t));
    return output;
}

unsigned int number(const std::string &value, unsigned int minimum, unsigned int maximum)
{
    size_t consumed;
    unsigned long result = std::stoul(value, &consumed);
    if (consumed != value.size() || result < minimum || result > maximum)
        throw std::runtime_error("invalid channel configuration");
    return result;
}

struct Channel {
    uint32_t physical;
    uint32_t tsid;
    std::u16string name;
};

std::string configuration_path()
{
    Dl_info info;
    if (!dladdr(reinterpret_cast<void *>(&configuration_path), &info))
        throw std::runtime_error("cannot locate BonDriver library");
    return std::string(info.dli_fname) + ".ini";
}

class BonDriver final : public IBonDriver2 {
    std::string socket_path = "/run/torne-0/control.sock";
    std::u16string name = u"Sony torne";
    const std::u16string space_name = u"地上デジタル";
    std::vector<Channel> channels;
    std::mutex api_lock;
    int control = -1;
    int stream = -1;
    DWORD current = unset_channel;
    std::thread reader;
    std::mutex buffer_lock;
    std::condition_variable ready;
    std::deque<std::vector<BYTE>> queue;
    std::vector<BYTE> last;
    bool receiving = false;
    uint64_t generation = 0;
    std::chrono::steady_clock::time_point signal_time;
    float signal = 0;
    STRUCT_IBONDRIVER2 adapter;

    void receive()
    {
        std::vector<BYTE> pending;
        BYTE input[chunk_size];
        unsigned int overflows = 0;
        for (;;) {
            uint64_t before;
            {
                std::lock_guard<std::mutex> lock(buffer_lock);
                if (!receiving)
                    break;
                before = generation;
            }
            ssize_t length = read(stream, input, sizeof(input));
            if (length < 0 && errno == EINTR)
                continue;
            if (length <= 0)
                break;
            pending.insert(pending.end(), input, input + length);
            const size_t size = pending.size() / 188 * 188;
            if (!size)
                continue;
            {
                std::lock_guard<std::mutex> lock(buffer_lock);
                if (!receiving)
                    break;
                if (before == generation) {
                    if (queue.size() == queue_size) {
                        queue.pop_front();
                        if (++overflows == 1 || overflows % 100 == 0)
                            std::fprintf(stderr, "BonDriver_Torne: TS receive buffer overflow (%u)\n", overflows);
                    }
                    queue.emplace_back(pending.begin(), pending.begin() + size);
                    ready.notify_all();
                }
            }
            pending.erase(pending.begin(), pending.begin() + size);
        }
        std::lock_guard<std::mutex> lock(buffer_lock);
        receiving = false;
        ready.notify_all();
    }

    void stop_reader()
    {
        {
            std::lock_guard<std::mutex> lock(buffer_lock);
            receiving = false;
            ready.notify_all();
        }
        if (stream >= 0)
            shutdown(stream, SHUT_RDWR);
        if (reader.joinable())
            reader.join();
        if (stream >= 0)
            close(stream);
        stream = -1;
        std::lock_guard<std::mutex> lock(buffer_lock);
        queue.clear();
        last.clear();
        generation++;
    }

    bool stop_tuner()
    {
        torne_reply reply = {};
        const bool stopped = control >= 0 && !torne_client_call(control, TORNE_COMMAND_STOP, 0, 0, &reply, nullptr);
        stop_reader();
        current = unset_channel;
        signal = 0;
        signal_time = {};
        return stopped;
    }

    BOOL get_stream(BYTE *destination, BYTE **pointer, DWORD *size, DWORD *remain)
    {
        if (!size || !remain || (!destination && !pointer))
            return false;
        *size = 0;
        *remain = 0;
        if (pointer)
            *pointer = nullptr;
        std::lock_guard<std::mutex> lock(buffer_lock);
        if (queue.empty())
            return false;
        last = std::move(queue.front());
        queue.pop_front();
        *size = last.size();
        *remain = queue.size();
        if (pointer)
            *pointer = last.data();
        else
            std::memcpy(destination, last.data(), last.size());
        return true;
    }

public:
    BonDriver()
    {
        std::ifstream config(configuration_path());
        std::string line, section, channel_path;
        while (std::getline(config, line)) {
            line = trim(line);
            if (line.empty() || line[0] == '#' || line[0] == ';')
                continue;
            if (line.front() == '[' && line.back() == ']') {
                section = line.substr(1, line.size() - 2);
                continue;
            }
            const auto separator = line.find('=');
            if (section != "Torne" || separator == std::string::npos)
                continue;
            const auto key = trim(line.substr(0, separator));
            const auto value = trim(line.substr(separator + 1));
            if (key == "Socket")
                socket_path = value;
            else if (key == "Name")
                name = utf16(value);
            else if (key == "Channels")
                channel_path = value;
        }
        if (socket_path.empty() || name.empty())
            throw std::runtime_error("empty tuner name or socket path");
        if (channel_path.empty()) {
            for (uint32_t physical = 13; physical <= 62; physical++)
                channels.push_back({ physical, 0, utf16(std::to_string(physical) + "ch") });
        } else {
            std::ifstream list(channel_path);
            if (!list)
                throw std::runtime_error("cannot open channel list");
            while (std::getline(list, line)) {
                if (trim(line).empty())
                    continue;
                std::istringstream row(line);
                std::string physical, tsid, label;
                if (!std::getline(row, physical, '\t') || !std::getline(row, tsid, '\t') ||
                    !std::getline(row, label) || trim(label).empty())
                    throw std::runtime_error("invalid channel list");
                channels.push_back({ number(physical, 13, 62), number(tsid, 0, 65535), utf16(trim(label)) });
            }
            if (channels.empty())
                throw std::runtime_error("empty channel list");
        }
        adapter.Initialize(this, nullptr);
    }

    ~BonDriver() { CloseTuner(); }

    const STRUCT_IBONDRIVER *structure() { return &adapter.st; }

    const BOOL OpenTuner() override
    {
        std::lock_guard<std::mutex> lock(api_lock);
        if (control >= 0) {
            struct pollfd connection = { control, POLLIN, 0 };
            if (poll(&connection, 1, 0) >= 0 && !(connection.revents & (POLLHUP | POLLERR | POLLNVAL)))
                return true;
            stop_reader();
            close(control);
            current = unset_channel;
        }
        control = torne_client_open(socket_path.c_str());
        if (control < 0)
            std::fprintf(stderr, "BonDriver_Torne: cannot open %s: %s\n", socket_path.c_str(), std::strerror(errno));
        return control >= 0;
    }

    void CloseTuner() override
    {
        std::lock_guard<std::mutex> lock(api_lock);
        if (control >= 0) {
            stop_tuner();
            close(control);
            control = -1;
        } else {
            stop_reader();
        }
    }

    const BOOL SetChannel(const BYTE channel) override { return SetChannel(0, channel); }

    const BOOL SetChannel(const DWORD space, const DWORD channel) override
    {
        std::lock_guard<std::mutex> lock(api_lock);
        if (control < 0 || space != 0 || channel >= channels.size())
            return false;
        {
            std::lock_guard<std::mutex> buffer(buffer_lock);
            if (channel == current && receiving)
                return true;
        }
        if (!stop_tuner())
            return false;
        torne_reply reply = {};
        if (torne_client_call(control, TORNE_COMMAND_TUNE, channels[channel].physical,
                              channels[channel].tsid, &reply, &stream)) {
            std::fprintf(stderr, "BonDriver_Torne: tune failed: %s\n", std::strerror(errno));
            return false;
        }
        {
            std::lock_guard<std::mutex> buffer(buffer_lock);
            receiving = true;
        }
        try {
            reader = std::thread(&BonDriver::receive, this);
        } catch (const std::system_error &error) {
            std::fprintf(stderr, "BonDriver_Torne: cannot start reader: %s\n", error.what());
            stop_tuner();
            return false;
        }
        current = channel;
        return true;
    }

    const float GetSignalLevel() override
    {
        std::lock_guard<std::mutex> lock(api_lock);
        if (control < 0 || current == unset_channel)
            return 0;
        auto now = std::chrono::steady_clock::now();
        if (now - signal_time >= std::chrono::seconds(1)) {
            torne_reply reply = {};
            signal = !torne_client_call(control, TORNE_COMMAND_STATUS, 0, 0, &reply, nullptr) && reply.locked
                ? std::max(0.0f, reply.cnr_x100 / 100.0f) : 0.0f;
            signal_time = now;
        }
        return signal;
    }

    const DWORD WaitTsStream(const DWORD timeout = 0) override
    {
        std::unique_lock<std::mutex> lock(buffer_lock);
        auto available = [this] { return !queue.empty() || !receiving; };
        if (timeout == UINT32_MAX)
            ready.wait(lock, available);
        else if (!ready.wait_for(lock, std::chrono::milliseconds(timeout), available))
            return wait_timeout;
        return queue.empty() ? wait_abandoned : 0;
    }

    const DWORD GetReadyCount() override
    {
        std::lock_guard<std::mutex> lock(buffer_lock);
        return queue.size();
    }

    const BOOL GetTsStream(BYTE *destination, DWORD *size, DWORD *remain) override
    {
        return get_stream(destination, nullptr, size, remain);
    }

    const BOOL GetTsStream(BYTE **destination, DWORD *size, DWORD *remain) override
    {
        return get_stream(nullptr, destination, size, remain);
    }

    void PurgeTsStream() override
    {
        std::lock_guard<std::mutex> lock(buffer_lock);
        queue.clear();
        generation++;
    }

    void Release() override { delete this; }
    const BON16CHAR *GetTunerName() override { return reinterpret_cast<const BON16CHAR *>(name.c_str()); }
    const BON16CHAR *EnumTuningSpace(const DWORD space) override
    {
        return space == 0 ? reinterpret_cast<const BON16CHAR *>(space_name.c_str()) : nullptr;
    }
    const BON16CHAR *EnumChannelName(const DWORD space, const DWORD channel) override
    {
        return space == 0 && channel < channels.size()
            ? reinterpret_cast<const BON16CHAR *>(channels[channel].name.c_str()) : nullptr;
    }
    const BOOL IsTunerOpening() override
    {
        std::lock_guard<std::mutex> lock(api_lock);
        return control >= 0;
    }
    const DWORD GetCurSpace() override
    {
        std::lock_guard<std::mutex> lock(api_lock);
        return current == unset_channel ? unset_channel : 0;
    }
    const DWORD GetCurChannel() override
    {
        std::lock_guard<std::mutex> lock(api_lock);
        return current;
    }
};

BonDriver *create()
{
    try {
        return new BonDriver;
    } catch (const std::exception &error) {
        std::fprintf(stderr, "BonDriver_Torne: %s\n", error.what());
        return nullptr;
    }
}

}

extern "C" IBonDriver *CreateBonDriver()
{
    return create();
}

extern "C" const STRUCT_IBONDRIVER *CreateBonStruct()
{
    auto driver = create();
    return driver ? driver->structure() : nullptr;
}
