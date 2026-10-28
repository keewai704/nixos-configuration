#define _GNU_SOURCE
#include <libusb-1.0/libusb.h>
#include <getopt.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include "torne_core.h"
#include "torne_dib.h"
#include "torne_card.h"
#include "card-socket.h"
#include "receiver-client.h"
#include "stream.h"

struct receiver {
    libusb_context *context;
    libusb_device_handle *usb;
    struct torne_bridge bridge;
    struct torne_dib dib;
    struct torne_card card;
    pthread_mutex_t lock;
    int card_listener;
    struct torne_stream *stream;
    unsigned int channel;
};

static volatile sig_atomic_t stopping;

static bool peer_closed(int fd)
{
    struct pollfd client = { .fd = fd, .events = POLLRDHUP };
    return poll(&client, 1, 0) > 0 &&
        (client.revents & (POLLHUP | POLLRDHUP | POLLERR | POLLNVAL));
}

static void stop(int signal_number)
{
    stopping = 1;
}

static uint64_t now_ms(void *private)
{
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return (uint64_t)time.tv_sec * 1000 + time.tv_nsec / 1000000;
}

static void sleep_ms(void *private, unsigned int milliseconds)
{
    struct receiver *receiver = private;
    torne_bridge_flush(&receiver->bridge);
    struct timespec delay = { milliseconds / 1000, (milliseconds % 1000) * 1000000 };
    while (nanosleep(&delay, &delay) < 0 && errno == EINTR && !stopping)
        ;
}

static void log_message(void *private, int level, const char *format, ...)
{
    va_list arguments;
    va_start(arguments, format);
    vfprintf(stderr, format, arguments);
    fputc('\n', stderr);
    va_end(arguments);
}

static int usb_error(int error)
{
    switch (error) {
    case LIBUSB_ERROR_TIMEOUT: return -ETIMEDOUT;
    case LIBUSB_ERROR_NO_DEVICE: return -ENODEV;
    case LIBUSB_ERROR_BUSY: return -EBUSY;
    case LIBUSB_ERROR_PIPE: return -EPIPE;
    case LIBUSB_ERROR_INTERRUPTED: return -EINTR;
    default: return -EIO;
    }
}

static int control(void *private, u8 type, u16 value, u16 index, void *buffer, u16 length)
{
    struct receiver *receiver = private;
    int result = libusb_control_transfer(receiver->usb, type, 0xbc, value, index, buffer, length, 1000);
    return result < 0 ? usb_error(result) : result;
}

static int bulk(void *private, u8 endpoint, void *buffer, int length, unsigned int timeout)
{
    struct receiver *receiver = private;
    int transferred = 0;
    int result = endpoint == 0x83
        ? libusb_interrupt_transfer(receiver->usb, endpoint, buffer, length, &transferred, timeout)
        : libusb_bulk_transfer(receiver->usb, endpoint, buffer, length, &transferred, timeout);
    if (result == LIBUSB_ERROR_TIMEOUT && transferred)
        return transferred;
    return result < 0 ? usb_error(result) : transferred;
}

static const struct torne_ops operations = {
    .control = control, .bulk = bulk, .msleep = sleep_ms, .now_ms = now_ms, .log = log_message,
};

static int listen_socket(const char *path, int type)
{
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    strcpy(address.sun_path, path);
    int fd = socket(AF_UNIX, type | SOCK_CLOEXEC, 0);
    if (fd < 0)
        return -1;
    unlink(path);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) < 0 || listen(fd, 8) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static int card_request(struct receiver *receiver, struct torne_card_message *message)
{
    if (message->size != _IOC_SIZE(message->command) || message->size > sizeof(message->data))
        return -EINVAL;
    switch (message->command) {
    case TORNE_CARD_IOC_PRESENT: {
        bool present;
        int result = torne_card_present(&receiver->card, &present);
        if (result)
            return result;
        int value = present;
        memcpy(message->data, &value, sizeof(value));
        if (!present)
            torne_card_invalidate(&receiver->card);
        return 0;
    }
    case TORNE_CARD_IOC_RESET:
    case TORNE_CARD_POWER_UP: {
        struct torne_card_atr atr = { .len = sizeof(atr.atr) };
        bool present;
        int result = torne_card_present(&receiver->card, &present);
        if (result)
            return result;
        if (!present) {
            torne_card_invalidate(&receiver->card);
            return -ENOMEDIUM;
        }
        if (message->command == TORNE_CARD_POWER_UP && receiver->card.open) {
            atr.len = receiver->card.atr_len;
            memcpy(atr.atr, receiver->card.atr, atr.len);
        } else {
            result = torne_card_reset(&receiver->card, atr.atr, &atr.len);
            if (result)
                return result;
        }
        memcpy(message->data, &atr, sizeof(atr));
        return 0;
    }
    case TORNE_CARD_IOC_TRANSMIT: {
        struct torne_card_apdu apdu;
        memcpy(&apdu, message->data, sizeof(apdu));
        if (!apdu.tx_len || apdu.tx_len > sizeof(apdu.tx) || !apdu.rx_len || apdu.rx_len > sizeof(apdu.rx))
            return -EINVAL;
        int result = torne_card_transmit(&receiver->card, apdu.tx, apdu.tx_len, apdu.rx, &apdu.rx_len);
        if (!result)
            memcpy(message->data, &apdu, sizeof(apdu));
        return result;
    }
    default:
        return -EINVAL;
    }
}

static void *serve_card(void *private)
{
    struct receiver *receiver = private;
    while (!stopping) {
        int fd = accept4(receiver->card_listener, NULL, NULL, SOCK_CLOEXEC);
        if (fd < 0)
            continue;
        struct torne_card_message message;
        ssize_t length;
        while ((length = recv(fd, &message, sizeof(message), MSG_TRUNC)) > 0) {
            if (length != sizeof(message))
                break;
            pthread_mutex_lock(&receiver->lock);
            message.result = card_request(receiver, &message);
            int flushed = torne_bridge_flush(&receiver->bridge);
            if (!message.result)
                message.result = flushed;
            if (receiver->bridge.err) {
                fputs("USB control failed; restarting receiver\n", stderr);
                exit(1);
            }
            pthread_mutex_unlock(&receiver->lock);
            if (send(fd, &message, sizeof(message), MSG_NOSIGNAL) != sizeof(message))
                break;
        }
        close(fd);
    }
    return NULL;
}

static void stop_capture(struct receiver *receiver)
{
    if (!receiver->stream)
        return;
    torne_stream_stop(receiver->stream);
    receiver->stream = NULL;
    receiver->channel = 0;
    pthread_mutex_lock(&receiver->lock);
    torne_bridge_stop_stream(&receiver->bridge);
    torne_dib_set_output(&receiver->dib, TORNE_OUT_HIGHZ);
    torne_bridge_flush(&receiver->bridge);
    if (receiver->bridge.err) {
        fputs("USB stream shutdown failed; restarting receiver\n", stderr);
        exit(1);
    }
    pthread_mutex_unlock(&receiver->lock);
}

static int start_capture(struct receiver *receiver, int owner, uint32_t channel, uint32_t tsid, int *output)
{
    if (channel < 13 || channel > 62 || tsid > 65535)
        return -EINVAL;
    if (peer_closed(owner))
        return -ECANCELED;
    stop_capture(receiver);
    uint64_t started = now_ms(NULL);
    pthread_mutex_lock(&receiver->lock);
    int result = peer_closed(owner) ? -ECANCELED : torne_bridge_prepare_stream(&receiver->bridge);
    if (!result)
        result = torne_dib_tune(&receiver->dib, (473143u + (channel - 13) * 6000u) * 1000u);
    if (!result && (stopping || peer_closed(owner)))
        result = -ECANCELED;
    if (!result)
        result = torne_dib_set_output(&receiver->dib, TORNE_OUT_PARALLEL_GATED);
    if (!result) {
        unsigned char stale[61440];
        for (unsigned int i = 0; i < 128; i++) {
            int drained = bulk(receiver, 0x81, stale, sizeof(stale), 2);
            if (drained == -ETIMEDOUT || drained == 0)
                break;
            if (drained < 0) {
                result = drained;
                break;
            }
        }
    }
    if (!result)
        result = torne_bridge_start_stream(&receiver->bridge);
    if (!result)
        result = torne_bridge_flush(&receiver->bridge);
    if (receiver->bridge.err) {
        fputs("USB control failed; restarting receiver\n", stderr);
        exit(1);
    }
    if (!result) {
        int sockets[2];
        if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sockets)) {
            result = -errno;
        } else {
            result = torne_stream_start(&receiver->stream, receiver->context, receiver->usb, sockets[0], tsid);
            if (result)
                close(sockets[1]);
            else
                *output = sockets[1];
        }
    }
    if (result) {
        torne_bridge_stop_stream(&receiver->bridge);
        torne_dib_set_output(&receiver->dib, TORNE_OUT_HIGHZ);
        torne_bridge_flush(&receiver->bridge);
    } else {
        receiver->channel = channel;
        fprintf(stderr, "RF%u ready in %llu ms\n", channel, (unsigned long long)(now_ms(NULL) - started));
    }
    pthread_mutex_unlock(&receiver->lock);
    return result;
}

static int receiver_status(struct receiver *receiver, struct torne_reply *reply)
{
    if (!receiver->channel)
        return 0;
    struct torne_dib_status status;
    pthread_mutex_lock(&receiver->lock);
    int result = torne_dib_status(&receiver->dib, &status);
    torne_bridge_flush(&receiver->bridge);
    if (receiver->bridge.err) {
        fputs("USB status failed; restarting receiver\n", stderr);
        exit(1);
    }
    pthread_mutex_unlock(&receiver->lock);
    if (result)
        return result;
    reply->locked = status.locked;
    reply->cnr_x100 = status.has_cnr ? status.cnr_x100 : 0;
    reply->strength_dbm_x1000 = status.has_strength ? status.strength_dbm_x1000 : 0;
    return 0;
}

static int usb_path(libusb_device *device, char *path, size_t capacity)
{
    uint8_t ports[8];
    int count = libusb_get_port_numbers(device, ports, sizeof(ports));
    if (count <= 0)
        return -1;
    int written = snprintf(path, capacity, "%u-", libusb_get_bus_number(device));
    for (int i = 0; i < count; i++) {
        if (written < 0 || (size_t)written >= capacity)
            return -1;
        int size = snprintf(path + written, capacity - written, "%s%u", i ? "." : "", ports[i]);
        if (size < 0)
            return -1;
        written += size;
    }
    return (size_t)written < capacity ? 0 : -1;
}

static int find_devices(libusb_context *context, const char *selected, libusb_device_handle **usb)
{
    libusb_device **devices;
    ssize_t count = libusb_get_device_list(context, &devices);
    if (count < 0)
        return -EIO;
    int result = selected ? -ENODEV : 0;
    for (ssize_t i = 0; i < count; i++) {
        struct libusb_device_descriptor descriptor;
        char path[64];
        if (libusb_get_device_descriptor(devices[i], &descriptor) ||
            descriptor.idVendor != TORNE_USB_VENDOR || descriptor.idProduct != TORNE_USB_PRODUCT ||
            usb_path(devices[i], path, sizeof(path)))
            continue;
        if (!selected) {
            printf("%s Sony CECH-ZD1 J\n", path);
        } else if (!strcmp(path, selected)) {
            int opened = libusb_open(devices[i], usb);
            result = opened ? usb_error(opened) : 0;
            break;
        }
    }
    libusb_free_device_list(devices, 1);
    return result;
}

static int daemon_main(const char *device, const char *directory)
{
    struct receiver receiver = { .lock = PTHREAD_MUTEX_INITIALIZER };
    int result = libusb_init(&receiver.context);
    if (result)
        return 1;
    result = find_devices(receiver.context, device, &receiver.usb);
    if (result) {
        fprintf(stderr, "Sony CECH-ZD1 J at %s is unavailable: %d\n", device, result);
        return 1;
    }
    result = libusb_claim_interface(receiver.usb, 0);
    if (!result)
        result = libusb_set_interface_alt_setting(receiver.usb, 0, 0);
    if (result) {
        fprintf(stderr, "USB claim failed: %s\n", libusb_error_name(result));
        return 1;
    }
    torne_bridge_init(&receiver.bridge, &operations, &receiver);
    receiver.bridge.log_level = TORNE_LOG_INFO;
    result = torne_bridge_start(&receiver.bridge);
    if (!result)
        result = torne_bridge_reset_demodulator(&receiver.bridge);
    torne_dib_setup(&receiver.dib, &receiver.bridge);
    if (!result)
        result = torne_dib_init(&receiver.dib);
    if (!result)
        result = torne_bridge_flush(&receiver.bridge);
    if (result) {
        fprintf(stderr, "USB initialization failed: %d\n", result);
        return 1;
    }
    torne_card_setup(&receiver.card, &receiver.bridge);
    char card_path[108], control_path[108];
    if (snprintf(card_path, sizeof(card_path), "%s/card.sock", directory) >= (int)sizeof(card_path) ||
        snprintf(control_path, sizeof(control_path), "%s/control.sock", directory) >= (int)sizeof(control_path))
        return 1;
    receiver.card_listener = listen_socket(card_path, SOCK_SEQPACKET);
    int listener = listen_socket(control_path, SOCK_SEQPACKET);
    if (receiver.card_listener < 0 || listener < 0)
        return 1;
    pthread_t card_thread;
    if (pthread_create(&card_thread, NULL, serve_card, &receiver))
        return 1;
    fprintf(stderr, "Direct USB receiver ready at %s (%s)\n", device, control_path);
    int owner = -1;
    while (!stopping) {
        int error = torne_stream_error(receiver.stream);
        if (error) {
            fprintf(stderr, "RF%u stream failed: %d\n", receiver.channel, error);
            stop_capture(&receiver);
            if (owner >= 0)
                close(owner);
            owner = -1;
            if (error == -ENODEV || error == -EIO || error == -ESTALE)
                exit(1);
        }
        struct pollfd incoming[2] = {
            { .fd = owner, .events = POLLIN | POLLRDHUP },
            { .fd = listener, .events = POLLIN },
        };
        if (poll(incoming, 2, 100) <= 0)
            continue;
        if (owner >= 0 && incoming[0].revents) {
            struct torne_request request;
            ssize_t length = recv(owner, &request, sizeof(request), MSG_TRUNC);
            if (length <= 0) {
                stop_capture(&receiver);
                close(owner);
                owner = -1;
            } else {
                struct torne_reply reply = { 0 };
                int stream = -1;
                if (length != sizeof(request) || request.version != TORNE_PROTOCOL_VERSION) {
                    reply.result = -EPROTO;
                } else if (request.command == TORNE_COMMAND_TUNE) {
                    reply.result = start_capture(&receiver, owner, request.channel, request.tsid, &stream);
                } else if (request.command == TORNE_COMMAND_STATUS) {
                    reply.result = receiver_status(&receiver, &reply);
                } else if (request.command == TORNE_COMMAND_STOP) {
                    stop_capture(&receiver);
                } else {
                    reply.result = -EINVAL;
                }
                int sent = torne_send_reply(owner, &reply, stream);
                if (stream >= 0)
                    close(stream);
                if (sent) {
                    stop_capture(&receiver);
                    close(owner);
                    owner = -1;
                }
            }
        }
        if (incoming[1].revents & POLLIN) {
            int fd = accept4(listener, NULL, NULL, SOCK_CLOEXEC);
            if (fd < 0)
                continue;
            struct timeval timeout = { 2, 0 };
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
            struct torne_reply reply = { .result = owner >= 0 ? -EBUSY : 0 };
            if (torne_send_reply(fd, &reply, -1) || owner >= 0)
                close(fd);
            else
                owner = fd;
        }
    }
    stop_capture(&receiver);
    exit(0);
}

static int tune_main(const char *socket_path, uint32_t channel, uint32_t tsid)
{
    int control_fd = torne_client_open(socket_path);
    if (control_fd < 0) {
        fprintf(stderr, "Cannot open tuner: %s\n", strerror(errno));
        return 1;
    }
    struct torne_reply reply = { 0 };
    int stream = -1;
    if (torne_client_call(control_fd, TORNE_COMMAND_TUNE, channel, tsid, &reply, &stream)) {
        fprintf(stderr, "Direct USB tuning failed: %s\n", strerror(errno));
        close(control_fd);
        return 1;
    }
    unsigned char buffer[65536];
    int result = 0;
    while (!stopping) {
        ssize_t length = read(stream, buffer, sizeof(buffer));
        if (length < 0 && errno == EINTR)
            continue;
        if (length <= 0) {
            result = 1;
            break;
        }
        ssize_t offset = 0;
        while (offset < length && !stopping) {
            ssize_t written = write(STDOUT_FILENO, buffer + offset, length - offset);
            if (written < 0 && errno == EINTR)
                continue;
            if (written <= 0) {
                close(stream);
                close(control_fd);
                return errno == EPIPE ? 0 : 1;
            }
            offset += written;
        }
    }
    close(stream);
    close(control_fd);
    return result;
}

static int parse_number(const char *argument, uint32_t minimum, uint32_t maximum, uint32_t *number)
{
    char *end;
    errno = 0;
    unsigned long value = strtoul(argument, &end, 10);
    if (errno || *end || !*argument || value < minimum || value > maximum)
        return -1;
    *number = value;
    return 0;
}

int main(int argc, char **argv)
{
    struct sigaction action = { .sa_handler = stop };
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    signal(SIGPIPE, SIG_IGN);
    umask(0007);
    if (argc == 2 && !strcmp(argv[1], "list")) {
        libusb_context *context;
        if (libusb_init(&context))
            return 1;
        int result = find_devices(context, NULL, NULL);
        libusb_exit(context);
        return result ? 1 : 0;
    }
    const struct option options[] = {
        { "device", required_argument, NULL, 'd' },
        { "socket-dir", required_argument, NULL, 'r' },
        { "socket", required_argument, NULL, 's' },
        { "ch", required_argument, NULL, 'c' },
        { "tsid", required_argument, NULL, 't' },
        { NULL, 0, NULL, 0 },
    };
    const char *device = NULL, *directory = "/run/torne-0", *socket_path = "/run/torne-0/control.sock";
    uint32_t channel = 0, tsid = 0;
    optind = 2;
    int option;
    if (argc < 2)
        goto usage;
    while ((option = getopt_long(argc, argv, "", options, NULL)) != -1) {
        switch (option) {
        case 'd': device = optarg; break;
        case 'r': directory = optarg; break;
        case 's': socket_path = optarg; break;
        case 'c': if (parse_number(optarg, 13, 62, &channel)) goto usage; break;
        case 't': if (parse_number(optarg, 0, 65535, &tsid)) goto usage; break;
        default: goto usage;
        }
    }
    if (optind != argc)
        goto usage;
    if (!strcmp(argv[1], "daemon") && device)
        return daemon_main(device, directory);
    if (!strcmp(argv[1], "tune") && channel)
        return tune_main(socket_path, channel, tsid);
usage:
    fputs("Usage: torne-receiver list | daemon --device USB-PORT --socket-dir DIR | tune --socket PATH --ch CHANNEL [--tsid TSID]\n", stderr);
    return 1;
}
