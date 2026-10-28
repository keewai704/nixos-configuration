#include <assert.h>
#include <stdio.h>

#include "driver/torne_bridge.c"
#undef LOG
#include "driver/torne_dib.c"

enum fault { NONE, SHORT_REPLY, WRONG_COUNT, BUS_ERROR, TIMEOUT, STALE, SHORT_WRITE };

struct device {
    u16 registers[2048];
    u8 reply[64];
    unsigned int sends, receives, controls, reads;
    u64 now;
    enum fault fault;
    bool stale_sent;
};

struct fixture {
    struct device device;
    struct torne_bridge bridge;
    struct torne_dib demod;
};

static int usb_control(void *priv, u8 type, u16 value, u16 index, void *data, u16 length)
{
    struct device *device = priv;
    assert(type == VENDOR_OUT);
    device->controls++;
    return length;
}

static int usb_bulk(void *priv, u8 endpoint, void *data, int length, unsigned int timeout)
{
    struct device *device = priv;
    u8 *bytes = data;
    if (endpoint == 0x02) {
        assert(length == 512);
        assert(be32(bytes) == be32(bytes + 508));
        unsigned int words = be32(bytes + 4) & 0xff;
        assert(words <= 125);
        unsigned int count = 0;
        memset(device->reply, 0, sizeof(device->reply));
        put_be32(device->reply, be32(bytes));
        for (unsigned int i = 0; i < words; i++) {
            u32 word = be32(bytes + 8 + i * 4);
            unsigned int reg = word >> 16 & 0x7ff;
            if (word & 0x10000000u) {
                assert(++i < words);
                u32 mask = be32(bytes + 8 + i * 4);
                assert((mask & 0xffff0000u) == 0x18000000u);
                device->registers[reg] = (device->registers[reg] & (u16)mask) | (u16)word;
            } else if (word & 0x40000000u) {
                assert(count < 14);
                put_be32(device->reply + 8 + count++ * 4, device->registers[reg]);
            } else {
                assert(!(word & 0x38000000u));
                device->registers[reg] = word;
            }
        }
        device->sends++;
        device->reads = count;
        put_be32(device->reply + 4, count);
        if (count == 14 && device->fault == SHORT_WRITE)
            return length - 1;
        return length;
    }
    assert(endpoint == 0x83 && length == 64);
    device->receives++;
    device->now++;
    memcpy(bytes, device->reply, length);
    if (device->reads == 14) {
        switch (device->fault) {
        case SHORT_REPLY:
            return 8;
        case WRONG_COUNT:
            put_be32(bytes + 4, 13);
            break;
        case BUS_ERROR:
            put_be32(bytes + 4, 14 | 2 << 16);
            break;
        case TIMEOUT:
            device->now += timeout;
            return -ETIMEDOUT;
        case STALE:
            if (!device->stale_sent) {
                put_be32(bytes, be32(bytes) - 1);
                device->stale_sent = true;
            }
            break;
        default:
            break;
        }
    }
    return 8 + device->reads * 4;
}

static u64 clock_ms(void *priv)
{
    return ((struct device *)priv)->now;
}

static void sleep_ms(void *priv, unsigned int ms)
{
    ((struct device *)priv)->now += ms;
}

static void reset(struct fixture *fixture)
{
    static const struct torne_ops ops = {
        .control = usb_control, .bulk = usb_bulk, .now_ms = clock_ms, .msleep = sleep_ms,
    };
    memset(fixture, 0, sizeof(*fixture));
    fixture->bridge.ops = &ops;
    fixture->bridge.priv = &fixture->device;
    fixture->bridge.command_enabled = true;
    fixture->bridge.command_sequence = 7;
    torne_dib_setup(&fixture->demod, &fixture->bridge);
    fixture->device.registers[568] = 0x101e;
    fixture->device.registers[570] = 3;
    fixture->device.registers[505] = 1;
    fixture->device.registers[493] = 1;
    fixture->device.registers[494] = 12;
    fixture->device.registers[499] = 3;
    fixture->device.registers[500] = 2;
    fixture->device.registers[481] = 1;
    fixture->device.registers[482] = 3;
    fixture->device.registers[487] = 1;
    fixture->device.registers[488] = 3;
}

int main(void)
{
    struct fixture fixture;
    reset(&fixture);
    fixture.device.registers[285] = 0xabcd;
    dib_modify_word(&fixture.demod, 285, 0x0ff0, 0x8003);
    assert(!fixture.demod.err && !fixture.device.sends);
    assert(dib_read_word(&fixture.demod, 285) == 0x8bc3);
    assert(fixture.device.sends == 1 && fixture.device.receives == 1);

    reset(&fixture);
    for (unsigned int i = 0; i < 124; i++)
        dib_write_word(&fixture.demod, 300 + i, i);
    fixture.device.registers[285] = 0xffff;
    dib_modify_word(&fixture.demod, 285, 0x0ff0, 0x8003);
    assert(!fixture.demod.err);
    assert(torne_bridge_flush(&fixture.bridge) == 0);
    assert(fixture.device.sends == 2 && fixture.device.receives == 1);
    assert(fixture.device.registers[285] == 0x8ff3);
    for (unsigned int i = 0; i < 124; i++)
        assert(fixture.device.registers[300 + i] == i);

    reset(&fixture);
    fixture.bridge.command_slot = 15;
    dib_modify_word(&fixture.demod, 285, 0, 0x1234);
    assert(torne_bridge_flush(&fixture.bridge) == 0);
    assert(fixture.bridge.command_slot == 0 && fixture.device.controls == 2);
    assert(fixture.device.registers[285] == 0x1234);

    reset(&fixture);
    u16 registers[14], values[14];
    for (unsigned int i = 0; i < 14; i++) {
        registers[i] = 330 - i * 2;
        fixture.device.registers[registers[i]] = 0x8100 + i;
    }
    assert(torne_i2c_read_words(&fixture.bridge, 0x12, registers, values, 15) == -EINVAL);
    assert(torne_i2c_read_words(&fixture.bridge, 0x12, registers, values, 0) == 0);
    assert(!fixture.device.sends);
    for (unsigned int i = 0; i < 112; i++)
        dib_write_word(&fixture.demod, 400 + i, i);
    assert(torne_i2c_read_words(&fixture.bridge, 0x12, registers, values, 14) == 0);
    assert(fixture.device.sends == 2 && fixture.device.receives == 1);
    for (unsigned int i = 0; i < 14; i++)
        assert(values[i] == 0x8100 + i);

    reset(&fixture);
    get_frontend(&fixture.demod);
    assert(!fixture.demod.err && fixture.device.sends == 3);
    assert(fixture.demod.c.transmission_mode == TRANSMISSION_8K);
    assert(fixture.demod.c.guard_interval == GUARD_1_4);
    assert(fixture.demod.c.isdbt_partial_reception == 1);
    assert(fixture.demod.c.layer[0].segment_count == 1);
    assert(fixture.demod.c.layer[0].interleaving == 4);
    assert(fixture.demod.c.layer[0].fec == FEC_1_2);
    assert(fixture.demod.c.layer[0].modulation == MODULATION_QPSK);
    assert(fixture.demod.c.layer[1].segment_count == 12);
    assert(fixture.demod.c.layer[1].interleaving == 2);
    assert(fixture.demod.c.layer[1].fec == FEC_3_4);
    assert(fixture.demod.c.layer[1].modulation == MODULATION_QAM64);

    for (enum fault fault = SHORT_REPLY; fault <= SHORT_WRITE; fault++) {
        reset(&fixture);
        fixture.device.fault = fault;
        get_frontend(&fixture.demod);
        if (fault == STALE) {
            assert(!fixture.demod.err && fixture.device.receives == 4);
            assert(fixture.demod.c.layer[1].segment_count == 12);
            continue;
        }
        int expected = fault == TIMEOUT ? -ETIMEDOUT :
                       fault == BUS_ERROR || fault == SHORT_WRITE ? -EIO : -EPROTO;
        assert(fixture.demod.err == expected);
        assert(!fixture.demod.c.layer[1].segment_count);
        unsigned int sends = fixture.device.sends;
        dib_modify_word(&fixture.demod, 285, 0, 1);
        assert(torne_bridge_flush(&fixture.bridge) == expected);
        assert(fixture.device.sends == sends);
    }
    puts("USB command batching, modify ordering, packet boundaries and failure checks passed");
    return 0;
}
