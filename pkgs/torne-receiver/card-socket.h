#ifndef TORNE_CARD_SOCKET_H
#define TORNE_CARD_SOCKET_H

#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include "torne_ioctl.h"

#define TORNE_CARD_POWER_UP _IOR('T', 0x13, struct torne_card_atr)
#define TORNE_CARD_SOCKET "/run/torne/card.sock"
#define TORNE_CAPTURE_SOCKET "/run/torne/capture.sock"

struct torne_capture_request {
    uint32_t channel;
    uint32_t tsid;
};

struct torne_card_message {
    uint32_t command;
    int32_t result;
    uint32_t size;
    unsigned char data[sizeof(struct torne_card_apdu)];
};

static int torne_socket_connect(const char *path, int type)
{
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    if (strlen(path) >= sizeof(address.sun_path)) {
        errno = ENAMETOOLONG;
        return -1;
    }
    strcpy(address.sun_path, path);
    int fd = socket(AF_UNIX, type | SOCK_CLOEXEC, 0);
    if (fd < 0)
        return -1;
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        int error = errno;
        close(fd);
        errno = error;
        return -1;
    }
    return fd;
}

static inline int torne_card_call(int fd, uint32_t command, void *data)
{
    struct torne_card_message message = { .command = command, .size = _IOC_SIZE(command) };
    if (message.size > sizeof(message.data)) {
        errno = EINVAL;
        return -1;
    }
    memcpy(message.data, data, message.size);
    if (send(fd, &message, sizeof(message), MSG_NOSIGNAL) != sizeof(message))
        return -1;
    if (recv(fd, &message, sizeof(message), MSG_TRUNC) != sizeof(message)) {
        errno = EIO;
        return -1;
    }
    if (message.result < 0) {
        errno = -message.result;
        return -1;
    }
    if (message.command != command || message.size != _IOC_SIZE(command)) {
        errno = EPROTO;
        return -1;
    }
    memcpy(data, message.data, message.size);
    return 0;
}
#endif
