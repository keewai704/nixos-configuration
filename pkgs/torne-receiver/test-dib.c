#include <assert.h>
#include <stdio.h>

#include "driver/torne_dib.c"

struct fake_bus {
    u64 now;
    u16 lock;
    int error;
};

static u64 clock_ms(void *priv)
{
    return ((struct fake_bus *)priv)->now;
}

static void sleep_ms(void *priv, unsigned int ms)
{
    ((struct fake_bus *)priv)->now += ms;
}

int torne_bridge_flush(struct torne_bridge *bridge)
{
    return bridge->err;
}

int torne_i2c_write(struct torne_bridge *bridge, u8 address, const u8 *data, unsigned int len)
{
    return ((struct fake_bus *)bridge->priv)->error;
}

int torne_i2c_write_read(struct torne_bridge *bridge, u8 address, const u8 *data,
                       unsigned int len, u8 *reply, unsigned int reply_len)
{
    struct fake_bus *bus = bridge->priv;
    assert(len == 2);
    u16 reg = (u16)data[0] << 8 | data[1];
    u16 value = reg == 568 ? bus->lock : 0;
    assert(reply_len == 2);
    reply[0] = value >> 8;
    reply[1] = value;
    return bus->error;
}

static struct torne_dib pending(struct torne_bridge *bridge)
{
    struct torne_dib demod;
    torne_dib_setup(&demod, bridge);
    demod.c.frequency = 539142857;
    demod.c.isdbt_layer_enabled = 3;
    demod.c.layer[0].segment_count = 1;
    demod.c.layer[1].segment_count = 12;
    demod.longest_intl_layer = 0;
    demod.tune_state = DEMOD_STEP10;
    demod.status = STATUS_LOCKED;
    demod.symbol_duration = 12;
    demod.timeout_ms = 1000;
    return demod;
}

static void expect_pending(struct torne_dib *demod)
{
    assert(dib_tune(demod) > 0);
    assert(demod->tune_state == DEMOD_STEP10);
    assert(demod->status == STATUS_LOCKED);
}

int main(void)
{
    const struct torne_ops ops = { .now_ms = clock_ms, .msleep = sleep_ms };
    struct fake_bus bus = { .now = 100, .lock = 0x105e };
    struct torne_bridge bridge = { .ops = &ops, .priv = &bus };
    struct torne_dib demod = pending(&bridge);

    assert(dib_tune(&demod) == 0);
    assert(demod.tune_state == DEMOD_STOP);
    assert(demod.status == STATUS_DATA_LOCKED);

    demod = pending(&bridge);
    demod.c.layer[0].segment_count = 12;
    demod.c.layer[1].segment_count = 1;
    demod.longest_intl_layer = 1;
    bus.lock = 0x109e;
    assert(dib_tune(&demod) == 0);
    assert(demod.status == STATUS_DATA_LOCKED);

    demod = pending(&bridge);
    demod.c.isdbt_layer_enabled = 7;
    demod.c.layer[1].segment_count = 6;
    demod.c.layer[2].segment_count = 6;
    bus.lock = 0x105e;
    expect_pending(&demod);
    bus.lock |= 0x20;
    assert(dib_tune(&demod) == 0);
    assert(demod.status == STATUS_DATA_LOCKED);

    demod = pending(&bridge);
    bus.lock = 0x105c;
    expect_pending(&demod);
    bus.lock = 0x005e;
    expect_pending(&demod);
    bus.lock = 0x105e;
    demod.c.layer[1].segment_count = 11;
    expect_pending(&demod);

    demod = pending(&bridge);
    bus.lock = 0;
    expect_pending(&demod);
    bus.now = 1001;
    assert(dib_tune(&demod) == 0);
    assert(demod.status == STATUS_TUNE_FAILED);

    demod = pending(&bridge);
    bus.now = 100;
    bus.lock = 0x80;
    assert(dib_tune(&demod) == 0);
    assert(demod.status == STATUS_DATA_LOCKED);
    assert(finish_tune(&demod, 0) == -EAGAIN);

    demod = pending(&bridge);
    bus.lock = 0x105e;
    bus.error = -EIO;
    assert(torne_dib_tune(&demod, demod.c.frequency) == -EIO);

    puts("DiB full-segment acquisition checks passed");
    return 0;
}
