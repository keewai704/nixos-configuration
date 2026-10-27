#define _GNU_SOURCE
#include <libusb-1.0/libusb.h>
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

struct receiver {
    libusb_context *context;
    libusb_device_handle *usb;
    struct torne_bridge bridge;
    struct torne_dib dib;
    struct torne_card card;
    pthread_mutex_t lock;
    int card_listener;
};

static volatile sig_atomic_t stopping;

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

static int send_all(int fd, const void *buffer, size_t length)
{
    const unsigned char *position = buffer;
    while (length && !stopping) {
        ssize_t sent = send(fd, position, length, MSG_NOSIGNAL);
        if (sent < 0 && errno == EINTR)
            continue;
        if (sent <= 0)
            return -1;
        position += sent;
        length -= sent;
    }
    return length ? -1 : 0;
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
            pthread_mutex_unlock(&receiver->lock);
            if (send(fd, &message, sizeof(message), MSG_NOSIGNAL) != sizeof(message))
                break;
        }
        close(fd);
    }
    return NULL;
}

static int capture(struct receiver *receiver, int fd, uint32_t channel)
{
    if (channel < 13 || channel > 62)
        return -EINVAL;
    uint64_t started = now_ms(NULL);
    pthread_mutex_lock(&receiver->lock);
    int result = torne_bridge_prepare_stream(&receiver->bridge);
    if (!result)
        result = torne_dib_tune(&receiver->dib, (473143u + (channel - 13) * 6000u) * 1000u);
    if (!result)
        result = torne_dib_set_output(&receiver->dib, TORNE_OUT_PARALLEL_GATED);
    if (!result)
        result = torne_bridge_start_stream(&receiver->bridge);
    if (!result)
        result = torne_bridge_flush(&receiver->bridge);
    pthread_mutex_unlock(&receiver->lock);
    int32_t status = result;
    if (send_all(fd, &status, sizeof(status)) || result)
        goto done;
    fprintf(stderr, "RF%u ready in %llu ms\n", channel, (unsigned long long)(now_ms(NULL) - started));
    unsigned char raw[61440], output[61440];
    struct torne_framer framer;
    torne_framer_reset(&framer);
    while (!stopping) {
        struct pollfd client = { .fd = fd, .events = POLLIN | POLLRDHUP };
        if (poll(&client, 1, 0) > 0 && client.revents & (POLLIN | POLLHUP | POLLRDHUP | POLLERR))
            break;
        int length = bulk(receiver, 0x81, raw, sizeof(raw), 100);
        if (length == -ETIMEDOUT || length == -EINTR)
            continue;
        if (length < 0) {
            result = length;
            break;
        }
        size_t written = torne_framer_feed(&framer, raw, length, output);
        if (written && send_all(fd, output, written))
            break;
    }
done:
    pthread_mutex_lock(&receiver->lock);
    torne_bridge_stop_stream(&receiver->bridge);
    torne_dib_set_output(&receiver->dib, TORNE_OUT_HIGHZ);
    torne_bridge_flush(&receiver->bridge);
    pthread_mutex_unlock(&receiver->lock);
    return result;
}

static int daemon_main(void)
{
    struct receiver receiver = { .lock = PTHREAD_MUTEX_INITIALIZER };
    int result = libusb_init(&receiver.context);
    if (result)
        return 1;
    receiver.usb = libusb_open_device_with_vid_pid(receiver.context, TORNE_USB_VENDOR, TORNE_USB_PRODUCT);
    if (!receiver.usb) {
        fputs("Sony CECH-ZD1 J is unavailable\n", stderr);
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
    receiver.card_listener = listen_socket(TORNE_CARD_SOCKET, SOCK_SEQPACKET);
    int listener = listen_socket(TORNE_CAPTURE_SOCKET, SOCK_STREAM);
    if (receiver.card_listener < 0 || listener < 0)
        return 1;
    pthread_t card_thread;
    if (pthread_create(&card_thread, NULL, serve_card, &receiver))
        return 1;
    fputs("Direct USB receiver ready\n", stderr);
    while (!stopping) {
        struct pollfd incoming = { .fd = listener, .events = POLLIN };
        if (poll(&incoming, 1, 250) <= 0)
            continue;
        int fd = accept4(listener, NULL, NULL, SOCK_CLOEXEC);
        if (fd < 0)
            continue;
        struct timeval timeout = { .tv_sec = 2 };
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
        uint32_t channel;
        if (recv(fd, &channel, sizeof(channel), MSG_WAITALL) == sizeof(channel)) {
            result = capture(&receiver, fd, channel);
            if (result)
                fprintf(stderr, "RF%u capture failed: %d\n", channel, result);
        }
        close(fd);
        if (result == -ENODEV)
            return 1;
    }
    exit(0);
}

static int tune_main(const char *argument)
{
    char *end;
    errno = 0;
    unsigned long value = strtoul(argument, &end, 10);
    if (errno || *end || !*argument || value < 13 || value > 62)
        return 1;
    uint32_t channel = value;
    int fd = torne_socket_connect(TORNE_CAPTURE_SOCKET, SOCK_STREAM);
    if (fd < 0 || send_all(fd, &channel, sizeof(channel)))
        return 1;
    int32_t status;
    if (recv(fd, &status, sizeof(status), MSG_WAITALL) != sizeof(status) || status) {
        fputs("Direct USB tuning failed\n", stderr);
        return 1;
    }
    unsigned char buffer[65536];
    while (!stopping) {
        ssize_t length = read(fd, buffer, sizeof(buffer));
        if (length < 0 && errno == EINTR)
            continue;
        if (length <= 0)
            break;
        ssize_t offset = 0;
        while (offset < length) {
            ssize_t written = write(STDOUT_FILENO, buffer + offset, length - offset);
            if (written < 0 && errno == EINTR && !stopping)
                continue;
            if (written <= 0)
                return 1;
            offset += written;
        }
    }
    close(fd);
    return 0;
}

int main(int argc, char **argv)
{
    struct sigaction action = { .sa_handler = stop };
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    signal(SIGPIPE, SIG_IGN);
    umask(0007);
    if (argc == 2 && !strcmp(argv[1], "daemon"))
        return daemon_main();
    if (argc == 4 && !strcmp(argv[1], "tune") && !strcmp(argv[2], "--ch"))
        return tune_main(argv[3]);
    fputs("Usage: torne-receiver daemon | tune --ch CHANNEL\n", stderr);
    return 1;
}
