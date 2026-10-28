#ifndef TORNE_RECEIVER_CLIENT_H
#define TORNE_RECEIVER_CLIENT_H

#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

#define TORNE_PROTOCOL_VERSION 1
#define TORNE_COMMAND_TUNE 1
#define TORNE_COMMAND_STATUS 2
#define TORNE_COMMAND_STOP 3

struct torne_request {
    uint32_t version;
    uint32_t command;
    uint32_t channel;
    uint32_t tsid;
};

struct torne_reply {
    int32_t result;
    uint32_t locked;
    int32_t cnr_x100;
    int32_t strength_dbm_x1000;
};

static inline int torne_send_reply(int fd, const struct torne_reply *reply, int stream)
{
    struct iovec vector = { (void *)reply, sizeof(*reply) };
    struct msghdr message = { 0 };
    union { struct cmsghdr alignment; unsigned char data[CMSG_SPACE(sizeof(int))]; } control = { 0 };
    message.msg_iov = &vector;
    message.msg_iovlen = 1;
    if (stream >= 0) {
        message.msg_control = control.data;
        message.msg_controllen = sizeof(control.data);
        struct cmsghdr *header = CMSG_FIRSTHDR(&message);
        header->cmsg_level = SOL_SOCKET;
        header->cmsg_type = SCM_RIGHTS;
        header->cmsg_len = CMSG_LEN(sizeof(int));
        memcpy(CMSG_DATA(header), &stream, sizeof(stream));
    }
    return sendmsg(fd, &message, MSG_NOSIGNAL) == sizeof(*reply) ? 0 : -1;
}

static inline int torne_receive_reply(int fd, struct torne_reply *reply, int *stream)
{
    struct iovec vector = { reply, sizeof(*reply) };
    struct msghdr message = { 0 };
    union { struct cmsghdr alignment; unsigned char data[CMSG_SPACE(sizeof(int) * 2)]; } control = { 0 };
    message.msg_iov = &vector;
    message.msg_iovlen = 1;
    message.msg_control = control.data;
    message.msg_controllen = sizeof(control.data);
    ssize_t length;
    do {
        length = recvmsg(fd, &message, MSG_CMSG_CLOEXEC);
    } while (length < 0 && errno == EINTR);
    int received = -1;
    bool invalid = length != sizeof(*reply) || (message.msg_flags & (MSG_TRUNC | MSG_CTRUNC));
    for (struct cmsghdr *header = CMSG_FIRSTHDR(&message); header; header = CMSG_NXTHDR(&message, header)) {
        if (header->cmsg_level != SOL_SOCKET || header->cmsg_type != SCM_RIGHTS)
            continue;
        size_t count = (header->cmsg_len - CMSG_LEN(0)) / sizeof(int);
        for (size_t i = 0; i < count; i++) {
            int value;
            memcpy(&value, CMSG_DATA(header) + i * sizeof(int), sizeof(value));
            if (received >= 0 || !stream) {
                close(value);
                invalid = true;
            } else {
                received = value;
            }
        }
    }
    if (invalid || reply->result || (stream && received < 0)) {
        if (received >= 0)
            close(received);
        errno = invalid ? EPROTO : reply->result ? -reply->result : EPROTO;
        return -1;
    }
    if (stream)
        *stream = received;
    return 0;
}

static inline int torne_client_open(const char *path)
{
    struct sockaddr_un address = { 0 };
    address.sun_family = AF_UNIX;
    if (strlen(path) >= sizeof(address.sun_path)) {
        errno = ENAMETOOLONG;
        return -1;
    }
    strcpy(address.sun_path, path);
    int fd = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
    if (fd < 0)
        return -1;
    struct timeval timeout = { 15, 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    struct torne_reply reply = { 0 };
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) < 0 ||
        torne_receive_reply(fd, &reply, NULL)) {
        int error = errno;
        close(fd);
        errno = error;
        return -1;
    }
    return fd;
}

static inline int torne_client_call(int fd, uint32_t command, uint32_t channel, uint32_t tsid,
                                   struct torne_reply *reply, int *stream)
{
    struct torne_request request = { TORNE_PROTOCOL_VERSION, command, channel, tsid };
    if (send(fd, &request, sizeof(request), MSG_NOSIGNAL) != sizeof(request))
        return -1;
    return torne_receive_reply(fd, reply, stream);
}

#endif
