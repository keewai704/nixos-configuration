#include <errno.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include "torne_core.h"
#include "stream.h"

#define TRANSFER_COUNT 8
#define TRANSFER_SIZE (192 * 256)
#define CHUNK_SIZE (TRANSFER_SIZE + 4096)
#define QUEUE_SIZE 128

struct chunk {
    size_t size;
    unsigned char data[CHUNK_SIZE];
};

struct torne_stream {
    libusb_context *context;
    int fd;
    pthread_t events, sender;
    bool events_started, sender_started, stopping;
    pthread_mutex_t lock;
    pthread_cond_t ready;
    struct libusb_transfer *transfers[TRANSFER_COUNT];
    unsigned char buffers[TRANSFER_COUNT][TRANSFER_SIZE];
    unsigned int active, head, count, overflows;
    struct chunk queue[QUEUE_SIZE];
    struct torne_framer framer;
    uint32_t tsid;
    bool verified, wrong_tsid;
    uint64_t deadline;
    int error;
};

static uint64_t milliseconds(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static unsigned int pat_tsid(const unsigned char *packet)
{
    if ((packet[1] & 0x9f) || packet[2] || !(packet[1] & 0x40) || (packet[3] & 0xc0))
        return 0;
    unsigned int control = (packet[3] >> 4) & 3;
    if (control != 1 && control != 3)
        return 0;
    unsigned int offset = 4 + (control == 3 ? packet[4] + 1 : 0);
    if (offset >= 188)
        return 0;
    offset += 1 + packet[offset];
    if (offset + 8 > 188 || packet[offset] != 0)
        return 0;
    unsigned int length = 3 + (((unsigned int)packet[offset + 1] & 15) << 8 | packet[offset + 2]);
    if (!(packet[offset + 1] & 0x80) || !(packet[offset + 5] & 1) ||
        length < 12 || length > 188 - offset)
        return 0;
    uint32_t crc = 0xffffffffu;
    for (unsigned int i = 0; i < length; i++) {
        crc ^= (uint32_t)packet[offset + i] << 24;
        for (unsigned int bit = 0; bit < 8; bit++)
            crc = crc & 0x80000000u ? (crc << 1) ^ 0x04c11db7u : crc << 1;
    }
    if (crc)
        return 0;
    return (unsigned int)packet[offset + 3] << 8 | packet[offset + 4];
}

static void transfer_complete(struct libusb_transfer *transfer)
{
    struct torne_stream *stream = transfer->user_data;
    pthread_mutex_lock(&stream->lock);
    stream->active--;
    if (!stream->stopping && !stream->error) {
        if (transfer->status != LIBUSB_TRANSFER_COMPLETED &&
            transfer->status != LIBUSB_TRANSFER_TIMED_OUT) {
            stream->error = transfer->status == LIBUSB_TRANSFER_NO_DEVICE ? -ENODEV : -EIO;
        } else if (transfer->actual_length) {
            unsigned char output[CHUNK_SIZE];
            size_t written = torne_framer_feed(&stream->framer, transfer->buffer,
                                               transfer->actual_length, output);
            size_t offset = 0;
            if (!stream->verified) {
                for (; offset < written; offset += 188) {
                    unsigned int tsid = pat_tsid(output + offset);
                    if (tsid == stream->tsid) {
                        stream->verified = true;
                        break;
                    }
                    if (tsid)
                        stream->wrong_tsid = true;
                }
            }
            if (written > offset) {
                if (stream->count == QUEUE_SIZE) {
                    if (++stream->overflows == 1 || stream->overflows % 100 == 0)
                        fprintf(stderr, "TS receive buffer overflow (%u)\n", stream->overflows);
                } else {
                    struct chunk *chunk = &stream->queue[(stream->head + stream->count) % QUEUE_SIZE];
                    chunk->size = written - offset;
                    memcpy(chunk->data, output + offset, chunk->size);
                    stream->count++;
                }
            }
        }
        if (!stream->verified && milliseconds() > stream->deadline)
            stream->error = stream->wrong_tsid ? -ESTALE : -EAGAIN;
        if (!stream->error) {
            int result = libusb_submit_transfer(transfer);
            if (result)
                stream->error = result == LIBUSB_ERROR_NO_DEVICE ? -ENODEV : -EIO;
            else
                stream->active++;
        }
    }
    pthread_cond_broadcast(&stream->ready);
    pthread_mutex_unlock(&stream->lock);
}

static void *serve_events(void *argument)
{
    struct torne_stream *stream = argument;
    for (;;) {
        pthread_mutex_lock(&stream->lock);
        unsigned int active = stream->active;
        pthread_mutex_unlock(&stream->lock);
        if (!active)
            break;
        struct timeval timeout = { 0, 100000 };
        int result = libusb_handle_events_timeout(stream->context, &timeout);
        if (result && result != LIBUSB_ERROR_INTERRUPTED) {
            pthread_mutex_lock(&stream->lock);
            stream->error = -EIO;
            pthread_cond_broadcast(&stream->ready);
            pthread_mutex_unlock(&stream->lock);
        }
    }
    return NULL;
}

static void *send_stream(void *argument)
{
    struct torne_stream *stream = argument;
    for (;;) {
        struct chunk chunk;
        pthread_mutex_lock(&stream->lock);
        while (!stream->count && !stream->stopping && !stream->error)
            pthread_cond_wait(&stream->ready, &stream->lock);
        if (stream->stopping || stream->error) {
            pthread_mutex_unlock(&stream->lock);
            break;
        }
        chunk = stream->queue[stream->head];
        stream->head = (stream->head + 1) % QUEUE_SIZE;
        stream->count--;
        pthread_mutex_unlock(&stream->lock);
        size_t offset = 0;
        while (offset < chunk.size) {
            ssize_t sent = send(stream->fd, chunk.data + offset, chunk.size - offset, MSG_NOSIGNAL);
            if (sent < 0 && errno == EINTR)
                continue;
            if (sent <= 0) {
                pthread_mutex_lock(&stream->lock);
                if (!stream->stopping)
                    stream->error = -EPIPE;
                pthread_mutex_unlock(&stream->lock);
                shutdown(stream->fd, SHUT_RDWR);
                return NULL;
            }
            offset += sent;
        }
    }
    shutdown(stream->fd, SHUT_RDWR);
    return NULL;
}

void torne_stream_stop(struct torne_stream *stream)
{
    if (!stream)
        return;
    pthread_mutex_lock(&stream->lock);
    stream->stopping = true;
    pthread_cond_broadcast(&stream->ready);
    pthread_mutex_unlock(&stream->lock);
    shutdown(stream->fd, SHUT_RDWR);
    for (unsigned int i = 0; i < TRANSFER_COUNT; i++)
        if (stream->transfers[i])
            libusb_cancel_transfer(stream->transfers[i]);
    if (stream->events_started)
        pthread_join(stream->events, NULL);
    else
        serve_events(stream);
    if (stream->sender_started)
        pthread_join(stream->sender, NULL);
    for (unsigned int i = 0; i < TRANSFER_COUNT; i++)
        libusb_free_transfer(stream->transfers[i]);
    close(stream->fd);
    pthread_cond_destroy(&stream->ready);
    pthread_mutex_destroy(&stream->lock);
    free(stream);
}

int torne_stream_start(struct torne_stream **output, libusb_context *context,
                       libusb_device_handle *usb, int fd, uint32_t tsid)
{
    struct torne_stream *stream = calloc(1, sizeof(*stream));
    if (!stream) {
        close(fd);
        return -ENOMEM;
    }
    stream->context = context;
    stream->fd = fd;
    stream->tsid = tsid;
    stream->verified = !tsid;
    stream->deadline = milliseconds() + 2000;
    pthread_mutex_init(&stream->lock, NULL);
    pthread_cond_init(&stream->ready, NULL);
    torne_framer_reset(&stream->framer);
    struct timeval timeout = { 2, 0 };
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    for (unsigned int i = 0; i < TRANSFER_COUNT; i++) {
        struct libusb_transfer *transfer = libusb_alloc_transfer(0);
        if (!transfer)
            goto failed;
        stream->transfers[i] = transfer;
        libusb_fill_bulk_transfer(transfer, usb, 0x81, stream->buffers[i], TRANSFER_SIZE,
                                 transfer_complete, stream, 500);
        pthread_mutex_lock(&stream->lock);
        int submitted = libusb_submit_transfer(transfer);
        if (!submitted)
            stream->active++;
        pthread_mutex_unlock(&stream->lock);
        if (submitted)
            goto failed;
    }
    if (pthread_create(&stream->events, NULL, serve_events, stream))
        goto failed;
    stream->events_started = true;
    if (pthread_create(&stream->sender, NULL, send_stream, stream))
        goto failed;
    stream->sender_started = true;
    *output = stream;
    return 0;
failed:
    torne_stream_stop(stream);
    return -EIO;
}

int torne_stream_error(struct torne_stream *stream)
{
    if (!stream)
        return 0;
    pthread_mutex_lock(&stream->lock);
    int error = stream->error;
    pthread_mutex_unlock(&stream->lock);
    return error;
}
