//
//  ORDJVU.m
//  OmniReader
//
//  A small, dependency-free DjVu container + hidden-text parser.
//
//  The ZP arithmetic coder and BZZ decompressor are a direct port of the
//  MIT-licensed DejaView implementation (github.com/Alpaq92/dejaview), which in
//  turn documents its tables as derived from the MIT-licensed DjvuNet. No code
//  from the GPL djvulibre tree is used here.
//
//  Scope: IFF container (DJVU / DJVM), INFO metadata and the TXTz / TXTa hidden
//  text layer, including the zone tree used to rebuild paragraphs. Page images
//  are *not* decoded; see ORDJVUDocument for the user-facing consequence.
//

#import "ORDJVU.h"
#import "ORText.h"

#include <stdlib.h>
#include <string.h>

#pragma mark - ZP adaptation tables (DjVu format constants)

static const uint16_t kZPP[256] = {
    32768,32768,32768,27581,27581,23877,23877,20921,20921,18451,18451,16341,16341,14513,14513,12917,
    12917,11517,11517,10277,10277,9131,9131,8071,8071,7099,7099,6213,6213,5411,5411,4691,
    4691,4047,4047,3477,3477,2973,2973,2531,2531,2145,2145,1809,1809,1521,1521,1273,
    1273,1061,1061,881,881,729,729,601,601,493,493,403,403,329,329,267,
    267,213,213,165,165,123,123,87,87,59,59,35,35,19,19,7,
    7,1,1,22165,9454,32768,3376,18458,1153,13689,378,9455,123,6520,40,4298,
    13,2909,52,1930,160,1295,279,856,490,564,324,371,564,245,851,161,
    1477,282,975,426,645,646,427,979,282,1477,186,2221,122,3276,491,4866,
    742,7041,1118,9455,1680,10341,2526,14727,3528,11417,4298,15199,2909,22165,1930,32768,
    1295,9454,856,3376,564,1153,371,378,245,123,161,40,282,13,426,52,
    646,160,979,279,1477,490,2221,324,3276,564,4866,851,7041,1477,9455,975,
    11124,645,8221,427,5909,282,4023,186,2663,491,1767,742,1174,1118,781,1680,
    518,2526,341,3528,225,11124,148,8221,392,5909,594,4023,899,2663,1351,1767,
    2018,1174,3008,781,4472,518,6618,341,9455,225,12814,148,17194,392,17533,594,
    24270,899,32768,1351,18458,2018,13689,3008,9455,4472,6520,6618,10341,9455,14727,12814,
    11417,17194,15199,17533,22165,24270,32768,32768,22165,18458,18458,0,0,0,0,0
};

static const uint16_t kZPM[256] = {
    0,0,0,4261,4261,7976,7976,11219,11219,14051,14051,16524,16524,18685,18685,20573,
    20573,22224,22224,23665,23665,24923,24923,26021,26021,26978,26978,27810,27810,28532,28532,29158,
    29158,29700,29700,30166,30166,30568,30568,30914,30914,31210,31210,31463,31463,31678,31678,31861,
    31861,32015,32015,32145,32145,32254,32254,32346,32346,32422,32422,32486,32486,32538,32538,32581,
    32581,32619,32619,32653,32653,32682,32682,32707,32707,32727,32727,32743,32743,32754,32754,32762,
    32762,32767,32767,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
};

static const uint8_t kZPUP[256] = {
    84,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,
    18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,
    34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,
    50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,
    66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,
    82,81,82,9,86,5,88,89,90,91,92,93,94,95,96,97,
    82,99,76,101,70,103,66,105,106,107,66,109,60,111,56,69,
    114,65,116,61,118,57,120,53,122,49,124,43,72,39,60,33,
    56,29,52,23,48,23,42,137,38,21,140,15,142,9,144,141,
    146,147,148,149,150,151,152,153,154,155,70,157,66,81,62,75,
    58,69,54,65,50,167,44,65,40,59,34,55,30,175,24,177,
    178,179,180,181,182,183,184,69,186,59,188,55,190,51,192,47,
    194,41,196,37,198,199,72,201,62,203,58,205,54,207,50,209,
    46,211,40,213,36,215,30,217,26,219,20,71,14,61,14,57,
    8,53,228,49,230,45,232,39,234,35,138,29,24,25,240,19,
    22,13,16,13,10,7,244,249,10,89,230,0,0,0,0,0
};

static const uint8_t kZPDN[256] = {
    145,4,3,1,2,3,4,5,6,7,8,9,10,11,12,13,
    14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,
    30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,
    46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,
    62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,
    78,79,80,85,226,6,176,143,138,141,112,135,104,133,100,129,
    98,127,72,125,102,123,60,121,110,119,108,117,54,115,48,113,
    134,59,132,55,130,51,128,47,126,41,62,37,66,31,54,25,
    50,131,46,17,40,15,136,7,32,139,172,9,170,85,168,248,
    166,247,164,197,162,95,160,173,158,165,156,161,60,159,56,71,
    52,163,48,59,42,171,38,169,32,53,26,47,174,193,18,191,
    222,189,218,187,216,185,214,61,212,53,210,49,208,45,206,39,
    204,195,202,31,200,243,64,239,56,237,52,235,48,233,44,231,
    38,229,34,227,28,225,22,223,16,221,220,63,8,55,224,51,
    2,47,87,43,246,37,244,33,238,27,236,21,16,15,8,241,
    242,7,10,245,2,1,83,250,2,143,246,0,0,0,0,0
};

/// ffzt[i] = number of leading 1-bits in byte i, from bit 7 downwards.
static const uint8_t kFFZT[256] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
    3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,
    4,4,4,4,4,4,4,4,5,5,5,5,6,6,7,8
};

#pragma mark - Byte stream

typedef struct {
    const uint8_t *bytes;
    NSUInteger length;
    NSUInteger pos;
} ORByteStream;

static inline ORByteStream ORStreamMake(const uint8_t *bytes, NSUInteger length) {
    ORByteStream stream;
    stream.bytes = bytes;
    stream.length = length;
    stream.pos = 0;
    return stream;
}

/// Next byte, or -1 past the end (the ZP coder relies on this).
static inline int ORReadByte(ORByteStream *stream) {
    if (stream->pos < stream->length) return stream->bytes[stream->pos++];
    return -1;
}

static inline uint32_t ORByteOrZero(ORByteStream *stream) {
    int value = ORReadByte(stream);
    return value < 0 ? 0u : (uint32_t)value;
}

static inline uint32_t ORRead16(ORByteStream *stream) {
    uint32_t a = ORByteOrZero(stream);
    uint32_t b = ORByteOrZero(stream);
    return (a << 8) | b;
}

static inline uint32_t ORRead24(ORByteStream *stream) {
    uint32_t a = ORByteOrZero(stream);
    uint32_t b = ORByteOrZero(stream);
    uint32_t c = ORByteOrZero(stream);
    return (a << 16) | (b << 8) | c;
}

#pragma mark - ZP arithmetic decoder

typedef struct {
    ORByteStream stream;
    uint32_t a;
    uint32_t code;
    uint32_t fence;
    uint32_t buffer;
    int scount;
    int delay;
    BOOL exhausted;
} ORZPCoder;

static int ORZPFfz(uint32_t x) {
    return x >= 0xff00 ? (int)kFFZT[x & 0xff] + 8 : (int)kFFZT[(x >> 8) & 0xff];
}

static void ORZPPreload(ORZPCoder *zp) {
    while (zp->scount <= 24) {
        int byte = ORReadByte(&zp->stream);
        if (byte < 0) {
            byte = 0xff;
            if (--zp->delay < 1) {
                zp->delay = 1;
                zp->exhausted = YES;
            }
        }
        zp->buffer = (zp->buffer << 8) | (uint32_t)byte;
        zp->scount += 8;
    }
}

static void ORZPInit(ORZPCoder *zp) {
    zp->a = 0;
    int byte = ORReadByte(&zp->stream);
    if (byte < 0) byte = 0xff;
    zp->code = (uint32_t)byte << 8;
    byte = ORReadByte(&zp->stream);
    if (byte < 0) byte = 0xff;
    zp->code |= (uint32_t)byte;
    zp->delay = 25;
    zp->scount = 0;
    zp->buffer = 0;
    zp->exhausted = NO;
    ORZPPreload(zp);
    zp->fence = zp->code >= 0x8000 ? 0x7fff : zp->code;
}

static uint32_t ORZPDecodeSub(ORZPCoder *zp, uint8_t *ctx, uint32_t index,
                              uint32_t state, uint32_t z) {
    uint32_t bit = state & 1;
    // ZPCODER: avoid interval reversion.
    uint32_t d = 0x6000 + ((z + zp->a) >> 2);
    if (z > d) z = d;
    if (z > zp->code) {
        // LPS branch.
        z = 0x10000 - z;
        zp->a += z;
        zp->code += z;
        ctx[index] = kZPDN[state];
        int shift = ORZPFfz(zp->a);
        zp->scount -= shift;
        zp->a = ((zp->a & 0xffff) << shift) & 0xffff;
        zp->code = ((((zp->code & 0xffff) << shift) & 0xffff) |
                    ((zp->buffer >> zp->scount) & ((1u << shift) - 1)));
        if (zp->scount < 16) ORZPPreload(zp);
        zp->fence = zp->code >= 0x8000 ? 0x7fff : zp->code;
        return bit ^ 1;
    }
    // MPS branch.
    if (zp->a >= kZPM[state]) ctx[index] = kZPUP[state];
    zp->scount -= 1;
    zp->a = (z << 1) & 0xffff;
    zp->code = (((zp->code & 0xffff) << 1) & 0xffff) |
               ((zp->buffer >> zp->scount) & 1);
    if (zp->scount < 16) ORZPPreload(zp);
    zp->fence = zp->code >= 0x8000 ? 0x7fff : zp->code;
    return bit;
}

/// Adaptive decode using context byte ctx[index]; adapts that byte in place.
static uint32_t ORZPDecode(ORZPCoder *zp, uint8_t *ctx, uint32_t index) {
    uint32_t state = ctx[index];
    uint32_t z = zp->a + kZPP[state];
    if (z <= zp->fence) {
        zp->a = z;
        return state & 1;
    }
    return ORZPDecodeSub(zp, ctx, index, state, z);
}

static uint32_t ORZPDecodeSubSimple(ORZPCoder *zp, uint32_t mps, uint32_t z) {
    if (z > zp->code) {
        z = 0x10000 - z;
        zp->a += z;
        zp->code += z;
        int shift = ORZPFfz(zp->a);
        zp->scount -= shift;
        zp->a = ((zp->a & 0xffff) << shift) & 0xffff;
        zp->code = ((((zp->code & 0xffff) << shift) & 0xffff) |
                    ((zp->buffer >> zp->scount) & ((1u << shift) - 1)));
        if (zp->scount < 16) ORZPPreload(zp);
        zp->fence = zp->code >= 0x8000 ? 0x7fff : zp->code;
        return mps ^ 1;
    }
    zp->scount -= 1;
    zp->a = (z << 1) & 0xffff;
    zp->code = (((zp->code & 0xffff) << 1) & 0xffff) |
               ((zp->buffer >> zp->scount) & 1);
    if (zp->scount < 16) ORZPPreload(zp);
    zp->fence = zp->code >= 0x8000 ? 0x7fff : zp->code;
    return mps;
}

/// Pass-through (equiprobable, no context) decode.
static uint32_t ORZPDecodePassThrough(ORZPCoder *zp) {
    return ORZPDecodeSubSimple(zp, 0, 0x8000 + (zp->a >> 1));
}

#pragma mark - BZZ decompressor

#define ORBZZ_MAXBLOCK 4096
#define ORBZZ_FREQMAX 4
#define ORBZZ_CTXIDS 3

static uint32_t ORZPDecodeRaw(ORZPCoder *zp, int bits) {
    uint32_t n = 1;
    uint32_t m = 1u << bits;
    while (n < m) n = (n << 1) | ORZPDecodePassThrough(zp);
    return n - m;
}

/// Mirrors the C decoder: ctx=ptr-1; n=1; while (n<m) decode(ctx[n]).
static uint32_t ORZPDecodeBinary(ORZPCoder *zp, uint8_t *ctx, uint32_t ptr, int bits) {
    uint32_t n = 1;
    uint32_t m = 1u << bits;
    uint32_t base = ptr - 1;
    while (n < m) {
        uint32_t bit = ORZPDecode(zp, ctx, base + n);
        n = (n << 1) | bit;
    }
    return n - m;
}

/// Decodes one BZZ block, or nil for the terminating empty block.
static NSData *ORBZZDecodeBlock(ORZPCoder *zp, uint8_t *ctx) {
    uint32_t size = ORZPDecodeRaw(zp, 24);
    if (size == 0) return nil;
    if (size > ORBZZ_MAXBLOCK * 1024) return nil;

    uint8_t *data = calloc(size, 1);
    if (!data) return nil;

    int fshift = 0;
    if (ORZPDecodePassThrough(zp)) {
        fshift += 1;
        if (ORZPDecodePassThrough(zp)) fshift += 1;
    }

    uint8_t mtf[256];
    for (int i = 0; i < 256; i++) mtf[i] = (uint8_t)i;
    uint32_t freq[ORBZZ_FREQMAX] = {0, 0, 0, 0};
    uint32_t fadd = 4;
    int mtfno = 3;
    NSInteger markerpos = -1;

    for (uint32_t i = 0; i < size; i++) {
        uint32_t ctxid = ORBZZ_CTXIDS - 1;
        if ((int)ctxid > mtfno) ctxid = (uint32_t)mtfno;
        uint32_t cx = 0;
        BOOL decoded = YES;

        if (ORZPDecode(zp, ctx, cx + ctxid)) {
            mtfno = 0;
            data[i] = mtf[0];
        } else {
            cx += ORBZZ_CTXIDS;
            if (ORZPDecode(zp, ctx, cx + ctxid)) {
                mtfno = 1;
                data[i] = mtf[1];
            } else {
                cx += ORBZZ_CTXIDS;
                BOOL found = NO;
                for (int level = 0; level < 7 && !found; level++) {
                    int bits = level + 1;
                    int base = 1 << (level + 1);     // 2, 4, 8, ... 128
                    if (ORZPDecode(zp, ctx, cx)) {
                        mtfno = base + (int)ORZPDecodeBinary(zp, ctx, cx + 1, bits);
                        data[i] = mtf[mtfno];
                        found = YES;
                        break;
                    }
                    cx += 1 + ((1 << bits) - 1);     // 2, 4, 8, ... 128
                }
                if (!found) {
                    mtfno = 256;
                    data[i] = 0;
                    markerpos = (NSInteger)i;
                    decoded = NO;
                }
            }
        }
        if (!decoded) continue;

        // Rotate the MTF table according to empirical frequencies.
        fadd = fadd + (fadd >> fshift);
        if (fadd > 0x10000000) {
            fadd >>= 24;
            for (int k = 0; k < ORBZZ_FREQMAX; k++) freq[k] >>= 24;
        }
        uint32_t fc = fadd;
        if (mtfno < ORBZZ_FREQMAX) fc = fc + freq[mtfno];
        int k = mtfno;
        while (k >= ORBZZ_FREQMAX) {
            mtf[k] = mtf[k - 1];
            k--;
        }
        while (k > 0 && fc >= freq[k - 1]) {
            mtf[k] = mtf[k - 1];
            freq[k] = freq[k - 1];
            k--;
        }
        mtf[k] = data[i];
        freq[k] = fc;
    }

    if (markerpos < 1 || markerpos >= (NSInteger)size) {
        free(data);
        return nil;
    }

    // Inverse Burrows-Wheeler transform.
    uint32_t *posn = calloc(size, sizeof(uint32_t));
    int32_t count[256];
    memset(count, 0, sizeof(count));
    if (!posn) {
        free(data);
        return nil;
    }
    for (uint32_t i = 0; i < (uint32_t)markerpos; i++) {
        uint8_t c = data[i];
        posn[i] = ((uint32_t)c << 24) | ((uint32_t)count[c] & 0xffffff);
        count[c]++;
    }
    for (uint32_t i = (uint32_t)markerpos + 1; i < size; i++) {
        uint8_t c = data[i];
        posn[i] = ((uint32_t)c << 24) | ((uint32_t)count[c] & 0xffffff);
        count[c]++;
    }
    int32_t last = 1;
    for (int i = 0; i < 256; i++) {
        int32_t tmp = count[i];
        count[i] = last;
        last += tmp;
    }
    NSInteger i = 0;
    NSInteger tail = (NSInteger)size - 1;
    while (tail > 0) {
        uint32_t n = posn[i];
        uint8_t c = (uint8_t)(n >> 24);
        tail--;
        data[tail] = c;
        i = count[c] + (NSInteger)(n & 0xffffff);
    }
    free(posn);
    if (i != markerpos) {
        free(data);
        return nil;
    }

    NSData *result = [NSData dataWithBytes:data length:size - 1]; // last byte is the consumed marker slot
    free(data);
    return result;
}

/// Decompresses a whole BZZ stream (one ZP coder, shared contexts).
static NSData *ORBZZDecompress(ORByteStream stream) {
    ORZPCoder zp;
    memset(&zp, 0, sizeof(zp));
    zp.stream = stream;
    ORZPInit(&zp);

    uint8_t *ctx = calloc(300, 1);
    NSMutableData *output = [NSMutableData data];
    if (ctx) {
        // A single malformed chunk must never exhaust memory.
        while (output.length < 32u * 1024u * 1024u) {
            NSData *block = ORBZZDecodeBlock(&zp, ctx);
            if (!block) break;
            [output appendData:block];
            if (zp.exhausted) break;
        }
        free(ctx);
    }
    return output;
}

#pragma mark - IFF container

@interface ORDJVUChunk : NSObject
@property (nonatomic, copy) NSString *chunkID;
@property (nonatomic, copy, nullable) NSString *formType;
@property (nonatomic) BOOL container;
@property (nonatomic) NSUInteger headerOffset;
@property (nonatomic) NSUInteger payloadOffset;
@property (nonatomic) NSUInteger payloadLength;
@property (nonatomic, copy) NSArray<ORDJVUChunk *> *children;
@end

@implementation ORDJVUChunk
- (instancetype)init {
    self = [super init];
    if (self) _children = @[];
    return self;
}
@end

static NSString *ORDJVUFourCC(const uint8_t *bytes, NSUInteger offset, NSUInteger limit) {
    if (offset + 4 > limit) return nil;
    char text[5] = {0, 0, 0, 0, 0};
    memcpy(text, bytes + offset, 4);
    NSString *value = [NSString stringWithUTF8String:text];
    if (value.length == 4) return value;
    return [[NSString alloc] initWithBytes:text length:4 encoding:NSISOLatin1StringEncoding];
}

static BOOL ORDJVUIsContainer(NSString *chunkID) {
    return [chunkID isEqualToString:@"FORM"] || [chunkID isEqualToString:@"LIST"] ||
           [chunkID isEqualToString:@"PROP"] || [chunkID isEqualToString:@"CAT "];
}

static NSArray<ORDJVUChunk *> *ORDJVUParseChunks(const uint8_t *bytes,
                                                 NSUInteger start,
                                                 NSUInteger end,
                                                 int depth) {
    NSMutableArray<ORDJVUChunk *> *chunks = [NSMutableArray array];
    if (depth > 12 || start >= end) return chunks;

    NSUInteger p = start;
    while (p + 8 <= end) {
        NSString *chunkID = ORDJVUFourCC(bytes, p, end);
        if (chunkID.length != 4) break;

        uint32_t size = ((uint32_t)bytes[p + 4] << 24) |
                        ((uint32_t)bytes[p + 5] << 16) |
                        ((uint32_t)bytes[p + 6] << 8) |
                        ((uint32_t)bytes[p + 7]);
        NSUInteger dataStart = p + 8;
        NSUInteger dataEnd = dataStart + (NSUInteger)size;
        if (dataEnd > end || dataEnd < dataStart) dataEnd = end;

        ORDJVUChunk *chunk = [[ORDJVUChunk alloc] init];
        chunk.chunkID = chunkID;
        chunk.headerOffset = p;
        chunk.payloadOffset = dataStart;
        chunk.payloadLength = dataEnd - dataStart;

        if (ORDJVUIsContainer(chunkID)) {
            chunk.container = YES;
            chunk.formType = ORDJVUFourCC(bytes, dataStart, dataEnd);
            chunk.children = ORDJVUParseChunks(bytes, dataStart + 4, dataEnd, depth + 1);
        }

        [chunks addObject:chunk];

        NSUInteger next = dataStart + (NSUInteger)size;
        if (size & 1) next += 1; // IFF chunks are padded to an even length
        if (next <= p) break;    // never loop on a corrupt size
        p = next;
    }
    return chunks;
}

static ORDJVUChunk *ORDJVUChild(ORDJVUChunk *parent, NSString *chunkID) {
    for (ORDJVUChunk *child in parent.children) {
        if ([child.chunkID isEqualToString:chunkID]) return child;
    }
    return nil;
}

#pragma mark - Text layer

/// Reads one zone. Returns NO when the stream is not a valid zone tree.
static BOOL ORDJVUReadZone(ORByteStream *stream,
                           BOOL hasParent, int64_t parentStart,
                           BOOL hasPrevious, int64_t previousStart, int64_t previousLength,
                           NSMutableArray<NSValue *> *paragraphs,
                           int64_t *outStart, int64_t *outLength,
                           int depth) {
    if (depth > 16) return NO;
    int type = ORReadByte(stream);
    if (type < 1 || type > 7) return NO;

    ORRead16(stream); // xmin
    ORRead16(stream); // ymin
    ORRead16(stream); // width
    ORRead16(stream); // height

    int64_t textStart = (int64_t)((int)ORRead16(stream) - 0x8000);
    uint32_t textLength = ORRead24(stream);

    if (hasPrevious) {
        textStart += previousStart + previousLength;
    } else if (hasParent) {
        textStart += parentStart;
    }

    uint32_t childCount = ORRead24(stream);
    if (childCount > 200000) return NO;

    if (type == 4 && textStart >= 0 && textLength > 0) { // paragraph
        [paragraphs addObject:[NSValue valueWithRange:
            NSMakeRange((NSUInteger)textStart, (NSUInteger)textLength)]];
    }

    BOOL havePrevious = NO;
    int64_t previousZoneStart = 0;
    int64_t previousZoneLength = 0;
    for (uint32_t i = 0; i < childCount; i++) {
        int64_t zoneStart = 0;
        int64_t zoneLength = 0;
        if (!ORDJVUReadZone(stream, YES, textStart, havePrevious,
                            previousZoneStart, previousZoneLength,
                            paragraphs, &zoneStart, &zoneLength, depth + 1)) {
            return NO;
        }
        previousZoneStart = zoneStart;
        previousZoneLength = zoneLength;
        havePrevious = YES;
    }

    if (outStart) *outStart = textStart;
    if (outLength) *outLength = (int64_t)textLength;
    return YES;
}

/// Joins OCR line fragments into one paragraph and removes end-of-line hyphens.
static NSString *ORDJVUNormalizeParagraph(NSString *raw) {
    if (raw.length == 0) return @"";
    NSArray<NSString *> *lines = [raw componentsSeparatedByCharactersInSet:
                                      [NSCharacterSet newlineCharacterSet]];
    NSMutableString *result = [NSMutableString string];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) continue;
        if (result.length == 0) {
            [result appendString:trimmed];
            continue;
        }
        if ([result hasSuffix:@"-"] || [result hasSuffix:@"\u2010"] || [result hasSuffix:@"\u00ad"]) {
            [result deleteCharactersInRange:NSMakeRange(result.length - 1, 1)];
            [result appendString:trimmed];
        } else {
            [result appendString:@" "];
            [result appendString:trimmed];
        }
    }
    // OCR sometimes emits runs of spaces.
    while ([result rangeOfString:@"  "].location != NSNotFound) {
        [result replaceOccurrencesOfString:@"  " withString:@" "
                                   options:0 range:NSMakeRange(0, result.length)];
    }
    return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

/// Used when the page has no zone tree: blank lines delimit paragraphs.
static NSArray<NSString *> *ORDJVUFallbackParagraphs(NSString *text) {
    NSMutableArray<NSString *> *blocks = [NSMutableArray array];
    NSMutableArray<NSString *> *buffer = [NSMutableArray array];
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:
                                      [NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) {
            if (buffer.count > 0) {
                [blocks addObject:[buffer componentsJoinedByString:@"\n"]];
                [buffer removeAllObjects];
            }
            continue;
        }
        [buffer addObject:trimmed];
    }
    if (buffer.count > 0) [blocks addObject:[buffer componentsJoinedByString:@"\n"]];

    NSMutableArray<NSString *> *paragraphs = [NSMutableArray array];
    for (NSString *block in blocks) {
        NSString *normalized = ORDJVUNormalizeParagraph(block);
        if (normalized.length > 0) [paragraphs addObject:normalized];
    }
    return paragraphs;
}

static NSString *ORDJVUHTMLFromParagraphs(NSArray<NSString *> *paragraphs) {
    NSMutableString *html = [NSMutableString string];
    for (NSString *paragraph in paragraphs) {
        [html appendFormat:@"<p>%@</p>\n", [ORText escapeHTML:paragraph]];
    }
    return html;
}

@interface ORDJVUPage ()
@property (nonatomic, readwrite) NSInteger index;
@property (nonatomic, readwrite) CGSize pixelSize;
@property (nonatomic, readwrite) NSInteger dpi;
@property (nonatomic, readwrite) NSString *text;
@property (nonatomic, readwrite) NSString *html;
@property (nonatomic, readwrite) BOOL hasText;
@end

@implementation ORDJVUPage
- (instancetype)init {
    self = [super init];
    if (self) {
        _text = @"";
        _html = @"";
        _pixelSize = CGSizeZero;
        _dpi = 300;
    }
    return self;
}
@end

#pragma mark - Document

@interface ORDJVUDocument ()
@property (nonatomic, strong) NSData *fileData;
@property (nonatomic, copy) NSString *documentType;
@property (nonatomic, strong) NSArray<ORDJVUChunk *> *pageChunks;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, ORDJVUPage *> *pageCache;
@property (nonatomic) NSInteger textPageCount;
@property (nonatomic, copy, nullable) NSString *cachedCombinedHTML;
@property (nonatomic, copy, nullable) NSString *cachedCombinedText;
@end

@implementation ORDJVUDocument

+ (instancetype)documentAtPath:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path
                                          options:NSDataReadingMappedIfSafe
                                            error:NULL];
    if (data.length < 12) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.DJVU" code:1
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"Файл DjVu пуст или повреждён."}];
        return nil;
    }
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    if (memcmp(bytes, "AT&T", 4) != 0) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.DJVU" code:2
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"Это не файл DjVu (нет сигнатуры AT&T)."}];
        return nil;
    }

    NSArray<ORDJVUChunk *> *top = ORDJVUParseChunks(bytes, 4, data.length, 0);
    ORDJVUChunk *root = top.firstObject;
    if (!root || !root.container) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.DJVU" code:3
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"Контейнер DjVu повреждён."}];
        return nil;
    }
    NSString *type = root.formType;
    if (![type isEqualToString:@"DJVU"] && ![type isEqualToString:@"DJVM"]) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.DJVU" code:4
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"Неизвестный тип DjVu-контейнера."}];
        return nil;
    }

    NSMutableArray<ORDJVUChunk *> *pages = [NSMutableArray array];
    if ([type isEqualToString:@"DJVU"]) {
        [pages addObject:root];
    } else {
        for (ORDJVUChunk *child in root.children) {
            if (child.container && [child.formType isEqualToString:@"DJVU"]) {
                [pages addObject:child];
            }
        }
    }
    if (pages.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.DJVU" code:5
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"В документе нет страниц."}];
        return nil;
    }

    ORDJVUDocument *document = [[ORDJVUDocument alloc] init];
    document.fileData = data;
    document.documentType = type;
    document.pageChunks = [document orderedPages:pages root:root];
    document.pageCache = [NSMutableDictionary dictionary];
    document.textPageCount = -1;
    return document;
}

/// The DIRM directory can list pages in a different order than the file. Use it
/// only when its entry count matches exactly, so a malformed directory can
/// never reshuffle a document.
- (NSArray<ORDJVUChunk *> *)orderedPages:(NSArray<ORDJVUChunk *> *)pages
                                    root:(ORDJVUChunk *)root {
    if (pages.count < 2) return pages;
    ORDJVUChunk *dirm = ORDJVUChild(root, @"DIRM");
    if (!dirm || dirm.payloadLength < 4) return pages;

    const uint8_t *bytes = (const uint8_t *)self.fileData.bytes;
    NSUInteger origin = dirm.payloadOffset;
    NSUInteger limit = origin + dirm.payloadLength;
    uint8_t version = bytes[origin];
    if ((version & 0x80) == 0) return pages; // not bundled: file order is authoritative
    NSUInteger p = origin + 1;
    if (p + 2 > limit) return pages;
    uint32_t files = ((uint32_t)bytes[p] << 8) | bytes[p + 1];
    p += 2;
    if (files != pages.count) return pages;
    if (p + (NSUInteger)files * 4 > limit) return pages;

    NSMutableArray<ORDJVUChunk *> *ordered = [NSMutableArray array];
    NSMutableSet<NSNumber *> *used = [NSMutableSet set];
    for (uint32_t i = 0; i < files; i++) {
        uint32_t offset = ((uint32_t)bytes[p] << 24) | ((uint32_t)bytes[p + 1] << 16) |
                          ((uint32_t)bytes[p + 2] << 8) | (uint32_t)bytes[p + 3];
        p += 4;
        ORDJVUChunk *match = nil;
        for (ORDJVUChunk *page in pages) {
            if (page.headerOffset != offset) continue;
            if ([used containsObject:@(page.headerOffset)]) continue;
            match = page;
            break;
        }
        if (!match) return pages;
        [used addObject:@(match.headerOffset)];
        [ordered addObject:match];
    }
    return ordered.count == pages.count ? ordered : pages;
}

- (NSInteger)pageCount {
    return (NSInteger)self.pageChunks.count;
}

- (BOOL)hasTextLayer {
    return self.textPageCount > 0;
}

- (NSInteger)textPageCount {
    if (_textPageCount < 0) {
        NSInteger count = 0;
        for (NSInteger i = 0; i < self.pageCount; i++) {
            if ([self pageAtIndex:i].hasText) count++;
        }
        _textPageCount = count;
    }
    return _textPageCount;
}

- (ORDJVUPage *)pageAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.pageCount) return nil;
    NSNumber *key = @(index);
    ORDJVUPage *cached = self.pageCache[key];
    if (cached) return cached;

    ORDJVUPage *page = [self buildPageAtIndex:index];
    self.pageCache[key] = page;
    return page;
}

- (ORDJVUPage *)buildPageAtIndex:(NSInteger)index {
    ORDJVUChunk *chunk = self.pageChunks[(NSUInteger)index];
    ORDJVUPage *page = [[ORDJVUPage alloc] init];
    page.index = index + 1;

    const uint8_t *bytes = (const uint8_t *)self.fileData.bytes;

    ORDJVUChunk *info = ORDJVUChild(chunk, @"INFO");
    if (info && info.payloadLength >= 2) {
        const uint8_t *b = bytes + info.payloadOffset;
        NSUInteger width = ((NSUInteger)b[0] << 8) | b[1];
        NSUInteger height = info.payloadLength >= 4 ? (((NSUInteger)b[2] << 8) | b[3]) : 0;
        page.pixelSize = CGSizeMake((CGFloat)width, (CGFloat)height);
        if (info.payloadLength >= 8 && b[7] != 0xff) {
            NSInteger dpi = ((NSInteger)b[7] << 8) | b[6];
            if (dpi >= 25 && dpi <= 6000) page.dpi = dpi;
        }
    }

    ORDJVUChunk *textChunk = ORDJVUChild(chunk, @"TXTz");
    if (!textChunk) textChunk = ORDJVUChild(chunk, @"TXTa");
    if (!textChunk || textChunk.payloadLength < 3) return page;

    NSData *raw = nil;
    ORByteStream stream = ORStreamMake(bytes + textChunk.payloadOffset, textChunk.payloadLength);
    if ([textChunk.chunkID isEqualToString:@"TXTz"]) {
        raw = ORBZZDecompress(stream);
    } else {
        raw = [NSData dataWithBytes:stream.bytes length:stream.length];
    }
    if (raw.length < 3) return page;

    const uint8_t *rawBytes = (const uint8_t *)raw.bytes;
    NSUInteger rawLength = raw.length;
    uint32_t textSize = ((uint32_t)rawBytes[0] << 16) |
                        ((uint32_t)rawBytes[1] << 8) |
                        (uint32_t)rawBytes[2];
    if (textSize > rawLength - 3) textSize = (uint32_t)(rawLength - 3);
    NSData *textData = [raw subdataWithRange:NSMakeRange(3, textSize)];

    NSString *text = [[NSString alloc] initWithData:textData encoding:NSUTF8StringEncoding];
    if (!text) text = [ORText stringFromData:textData];
    page.text = text ?: @"";

    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSUInteger position = 3 + (NSUInteger)textSize;
    if (position < rawLength && rawBytes[position] == 1) {
        ORByteStream zoneStream = ORStreamMake(rawBytes, rawLength);
        zoneStream.pos = position + 1;
        int64_t zoneStart = 0;
        int64_t zoneLength = 0;
        BOOL ok = ORDJVUReadZone(&zoneStream, NO, 0, NO, 0, 0,
                                 ranges, &zoneStart, &zoneLength, 0);
        if (!ok) [ranges removeAllObjects];
    }

    NSMutableArray<NSString *> *paragraphs = [NSMutableArray array];
    for (NSValue *value in ranges) {
        NSRange range = value.rangeValue;
        if (range.location > textData.length ||
            range.length > textData.length - range.location) {
            [paragraphs removeAllObjects];
            break;
        }
        NSData *slice = [textData subdataWithRange:range];
        NSString *piece = [[NSString alloc] initWithData:slice encoding:NSUTF8StringEncoding];
        if (!piece) piece = [ORText stringFromData:slice];
        NSString *normalized = ORDJVUNormalizeParagraph(piece ?: @"");
        if (normalized.length > 0) [paragraphs addObject:normalized];
    }

    if (paragraphs.count == 0) {
        [paragraphs addObjectsFromArray:ORDJVUFallbackParagraphs(page.text)];
    }

    page.html = ORDJVUHTMLFromParagraphs(paragraphs);
    page.hasText = page.html.length > 0;
    return page;
}

- (NSString *)combinedHTML {
    if (self.cachedCombinedHTML) return self.cachedCombinedHTML;
    NSMutableString *html = [NSMutableString string];
    NSInteger chapter = 0;
    for (NSInteger i = 0; i < self.pageCount; i++) {
        ORDJVUPage *page = [self pageAtIndex:i];
        if (!page.hasText) continue;
        [html appendFormat:@"<section id=\"ch-%ld\" data-chapter=\"%ld\">",
                           (long)chapter, (long)chapter];
        [html appendString:page.html];
        [html appendString:@"</section>\n"];
        chapter++;
    }
    self.cachedCombinedHTML = [html copy];
    return self.cachedCombinedHTML;
}

- (NSString *)combinedPlainText {
    if (self.cachedCombinedText) return self.cachedCombinedText;
    NSMutableArray<NSString *> *pages = [NSMutableArray array];
    for (NSInteger i = 0; i < self.pageCount; i++) {
        ORDJVUPage *page = [self pageAtIndex:i];
        if (page.text.length == 0) continue;
        [pages addObject:page.text];
    }
    self.cachedCombinedText = [pages componentsJoinedByString:@"\n\n"];
    return self.cachedCombinedText;
}

+ (NSString *)readerCSS {
    return @".dj-source{font-size:.8em;opacity:.65;text-align:center;margin:0 0 1.2em;}"
           "p{margin:0 0 .55em;}";
}

@end
