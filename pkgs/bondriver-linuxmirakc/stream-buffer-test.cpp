#include "type_compat.h"
#include "GrabTsData.hpp"

#include <atomic>
#include <cassert>
#include <chrono>
#include <future>
#include <thread>
#include <vector>

int main()
{
    using namespace std::chrono_literals;
    GrabTsData buffer;
    std::vector<BYTE> packet(DATA_BUF_SIZE, 0x47);
    std::atomic<unsigned> written{0};
    auto producer = std::async(std::launch::async, [&] {
        while (buffer.put_TsStream(packet.data(), packet.size())) {
            ++written;
        }
    });
    const auto deadline = std::chrono::steady_clock::now() + 5s;
    while (written < RING_BUF_SIZE / DATA_BUF_SIZE - 1) {
        assert(std::chrono::steady_clock::now() < deadline);
        std::this_thread::yield();
    }
    assert(producer.wait_for(100ms) == std::future_status::timeout);
    buffer.stop_TsStream();
    assert(producer.wait_for(1s) == std::future_status::ready);
    producer.get();

    buffer.purge_TsStream();
    BYTE* data = nullptr;
    DWORD size = 0, remaining = 0;
    assert(!buffer.get_TsStream(&data, &size, &remaining));
    assert(buffer.put_TsStream(packet.data(), packet.size()));
    assert(buffer.get_TsStream(&data, &size, &remaining));
    assert(size == packet.size() && remaining == 0);
    assert(std::vector<BYTE>(data, data + size) == packet);
}
