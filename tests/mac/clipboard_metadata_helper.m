// AppKit setup for the assembly fixture. This helper is never linked into rhun.
#import <AppKit/AppKit.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { uint64_t value, aux; } Result;
extern Result fixture_call(void *, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
#define CORE(name) extern void name(void) __asm__(#name)
CORE(clip_wire_encode); CORE(clip_wire_decode); CORE(mem_free);
CORE(mac_clip_write_board); CORE(mac_clip_read_native); CORE(mac_clip_read);
CORE(mac_clip_paste_board_tagged); CORE(ed_clip_set); CORE(ed_clip_set_metadata);
CORE(doc_new); CORE(doc_free); CORE(doc_insert); CORE(doc_len); CORE(doc_copy);
CORE(doc_selections_set); CORE(doc_selections_get); CORE(doc_undo); CORE(doc_redo);
CORE(editor_multi_copy); CORE(app_clip_request); CORE(app_clip_reset);
CORE(fixture_probe_read); CORE(fixture_probe_write);
CORE(fixture_private_write); CORE(fixture_private_get); CORE(fixture_accept); CORE(fixture_hold);
extern uint64_t g_plat[] __asm__("g_plat");
extern uint64_t g_doc __asm__("g_doc");
extern uint64_t g_mem_live __asm__("g_mem_live");
extern uint64_t app_clip_active_token __asm__("app_clip_active_token");
extern uint32_t g_focus __asm__("g_focus");
extern uint32_t cfg_vim __asm__("cfg_vim");
void *test_clip_board;
#define C0(f) fixture_call((void *)f,0,0,0,0,0,0)
#define C1(f,a) fixture_call((void *)f,(uint64_t)(a),0,0,0,0,0)
#define C2(f,a,b) fixture_call((void *)f,(uint64_t)(a),(uint64_t)(b),0,0,0,0)
#define C3(f,a,b,c) fixture_call((void *)f,(uint64_t)(a),(uint64_t)(b),(uint64_t)(c),0,0,0)
#define C4(f,a,b,c,d) fixture_call((void *)f,(uint64_t)(a),(uint64_t)(b),(uint64_t)(c),(uint64_t)(d),0,0)
#define C5(f,a,b,c,d,e) fixture_call((void *)f,(uint64_t)(a),(uint64_t)(b),(uint64_t)(c),(uint64_t)(d),(uint64_t)(e),0)
typedef struct { uint64_t offset, length; } Segment;
typedef struct { uint64_t count, total; Segment segments[2]; } Metadata;
typedef struct { void *text; uint64_t length, line; void *metadata; } View;
static NSString *const NativeType = @"com.r13.rhun.clipboard.v1";
static const uint64_t WireMax = (64ULL << 20) + 8224;
static NSPasteboard *currentBoard;
static const uint8_t unicodeText[] = {0xc3,0xa9,0,0xe6,0xb0,0xb4,0xf0,0x9f,0x98,0x80};
static const Metadata pieces = {2,5,{{0,3},{4,1}}};
static void failure(int line) {
    fprintf(stderr,"FAIL mac clipboard metadata line %d\n",line);
    [currentBoard releaseGlobally];
    exit(1);
}
#define CHECK(x) do { if (!(x)) failure(__LINE__); } while (0)
static NSData *textData(NSString *text) { return [text dataUsingEncoding:NSUTF8StringEncoding]; }
static void selectPairs(uint64_t document, const uint64_t *pairs, uint64_t count) {
    CHECK(C3(doc_selections_set,document,pairs,count).value == 1);
}
static uint64_t document(NSData *text) {
    uint64_t doc = C0(doc_new).value;
    CHECK(doc != 0);
    g_doc = doc;
    C5(doc_insert,doc,0,text.bytes,text.length,0);
    return doc;
}
static NSData *documentBytes(uint64_t doc) {
    uint64_t length = C1(doc_len,doc).value;
    NSMutableData *result = [NSMutableData dataWithLength:(NSUInteger)length];
    C4(doc_copy,doc,0,length,result.mutableBytes);
    return result;
}
static void freeDocument(uint64_t doc) { C1(doc_free,doc); g_doc = 0; }
static void clearCache(void) {
    g_plat[13] = (uint64_t)fixture_accept;
    CHECK(C3(ed_clip_set,0,0,0).value == 1);
    g_plat[13] = (uint64_t)fixture_private_write;
}
static NSData *wire(NSData *text, BOOL line, const Metadata *metadata) {
    Result result = C4(clip_wire_encode,text.bytes,text.length,line,metadata);
    CHECK(result.value != 0);
    NSData *copy = [NSData dataWithBytes:(void *)result.value length:(NSUInteger)result.aux];
    C1(mem_free,result.value);
    return copy;
}
static NSPasteboardItem *item(NSData *native, NSString *plain) {
    NSPasteboardItem *result = [[NSPasteboardItem alloc] init];
    if (native) CHECK([result setData:native forType:NativeType]);
    if (plain) CHECK([result setString:plain forType:NSPasteboardTypeString]);
    return result;
}
static void publish(NSPasteboard *board, NSArray<NSPasteboardItem *> *items) {
    [board clearContents];
    CHECK([board writeObjects:items]);
}
static NSData *caseText(NSString *kind) {
    if ([kind isEqualToString:@"unicode"]) return [NSData dataWithBytes:unicodeText length:sizeof unicodeText];
    if ([kind isEqualToString:@"empty"]) return [NSData data];
    if ([kind isEqualToString:@"line"]) return textData(@"L\n");
    return textData(@"raw");
}
static void writeCase(NSPasteboard *board, NSString *kind) {
    test_clip_board = (__bridge void *)board;
    if ([kind isEqualToString:@"multi"]) {
        uint64_t doc = document(textData(@"a\nb\nc"));
        const uint64_t pairs[] = {3,0,5,4};
        selectPairs(doc,pairs,2);
        CHECK(C2(editor_multi_copy,doc,0).value == 1);
        freeDocument(doc);
    } else if ([kind isEqualToString:@"malformed"]) {
        publish(board,@[item(textData(@"broken"),@"fallback")]);
    } else if ([kind isEqualToString:@"version"]) {
        NSMutableData *invalid = [wire(textData(@"raw"),NO,NULL) mutableCopy];
        ((uint32_t *)invalid.mutableBytes)[2] = 2;
        publish(board,@[item(invalid,@"fallback")]);
    } else if ([kind isEqualToString:@"native-only"]) {
        publish(board,@[item(wire(textData(@"raw"),NO,NULL),nil)]);
    } else if ([kind isEqualToString:@"native-first"]) {
        publish(board,@[item(wire(textData(@"raw"),NO,NULL),@"first"),item(nil,@"second")]);
    } else if ([kind isEqualToString:@"native-second"]) {
        publish(board,@[item(nil,@"first"),item(wire(textData(@"raw"),NO,NULL),@"second")]);
    } else if ([kind isEqualToString:@"plain"]) {
        publish(board,@[item(nil,@"plain")]);
    } else {
        NSData *text = caseText(kind);
        CHECK(C4(ed_clip_set_metadata,text.bytes,text.length,[kind isEqualToString:@"line"],0).value == 1);
    }
}
static NSData *expectedText(NSString *kind) {
    if ([kind isEqualToString:@"multi"]) return textData(@"a\nb|c");
    if ([kind isEqualToString:@"line"]) return textData(@"L\nabc");
    if ([kind isEqualToString:@"empty"]) return textData(@"abc");
    if ([kind isEqualToString:@"malformed"] || [kind isEqualToString:@"version"]) return textData(@"fallback");
    if ([kind hasPrefix:@"native-"] && ![kind isEqualToString:@"native-only"]) return textData(@"first\nsecond");
    if ([kind isEqualToString:@"native-only"]) return textData(@"raw");
    if ([kind isEqualToString:@"plain"]) return textData(@"plain");
    return caseText(kind);
}
static void readCase(NSPasteboard *board, NSString *kind) {
    test_clip_board = (__bridge void *)board;
    clearCache();             // Force retrieval with no matching local copy metadata.
    NSData *initial = [NSData data];
    if ([kind isEqualToString:@"multi"]) initial = textData(@"|");
    if ([kind isEqualToString:@"line"] || [kind isEqualToString:@"empty"]) initial = textData(@"abc");
    uint64_t doc = document(initial);
    if ([kind isEqualToString:@"multi"]) {
        const uint64_t pairs[] = {0,0,1,1}; selectPairs(doc,pairs,2);
    } else if ([kind isEqualToString:@"line"]) {
        const uint64_t pairs[] = {1,1}; selectPairs(doc,pairs,1);
    } else if ([kind isEqualToString:@"empty"]) {
        const uint64_t pairs[] = {3,0}; selectPairs(doc,pairs,1);
    }
    CHECK(C0(app_clip_request).value == 1);
    CHECK(app_clip_active_token == 0);
    CHECK([documentBytes(doc) isEqualToData:expectedText(kind)]);
    if (![kind isEqualToString:@"empty"]) {
        C1(doc_undo,doc); CHECK([documentBytes(doc) isEqualToData:initial]);
        C1(doc_redo,doc); CHECK([documentBytes(doc) isEqualToData:expectedText(kind)]);
    } else {
        Result selection = C2(doc_selections_get,doc,0);
        CHECK(selection.value == 3 && selection.aux == 0);
    }
    freeDocument(doc);
    clearCache();
}
static void checkRaw(NSPasteboard *board, NSData *expected) {
    uint64_t live = g_mem_live;
    Result result = C2(fixture_probe_read,(__bridge void *)board,expected.length);
    CHECK(result.value != 0 && result.aux == expected.length);
    CHECK(g_mem_live == live + 1);
    CHECK(memcmp((void *)result.value,expected.bytes,expected.length) == 0);
    CHECK(((uint8_t *)result.value)[result.aux] == 0);
    [board clearContents];
    CHECK(memcmp((void *)result.value,expected.bytes,expected.length) == 0);
    C1(mem_free,result.value);
    CHECK(g_mem_live == live);
}
static void rawAndRejectionTests(NSPasteboard *board) {
    NSData *text = textData(@"a\nb\nc");
    NSData *expected = wire(text,NO,&pieces);
    NSMutableData *source = [expected mutableCopy];
    CHECK(C3(fixture_probe_write,(__bridge void *)board,source.bytes,source.length).value == 1);
    [source resetBytesInRange:NSMakeRange(0,source.length)];
    CHECK(board.pasteboardItems.count == 1);
    CHECK([board.pasteboardItems[0] dataForType:NativeType] != nil);
    CHECK([textData([board stringForType:NSPasteboardTypeString]) isEqualToData:text]);
    NSInteger changes = board.changeCount;
    const uint8_t invalid[] = {0xff};
    CHECK(C3(fixture_probe_write,(__bridge void *)board,invalid,sizeof invalid).value == 0);
    CHECK(board.changeCount == changes);
    CHECK([[board.pasteboardItems[0] dataForType:NativeType] isEqualToData:expected]);
    CHECK(C3(fixture_probe_write,0,1,UINT64_MAX).value == 0);
    uint64_t live = g_mem_live;
    Result shortRead = C2(fixture_probe_read,(__bridge void *)board,expected.length-1);
    CHECK(shortRead.value == 0 && shortRead.aux == 0 && g_mem_live == live);
    Result invalidLimit = C2(fixture_probe_read,(__bridge void *)board,WireMax+1);
    CHECK(invalidLimit.value == 0 && invalidLimit.aux == 0 && g_mem_live == live);
    Result missing = C2(fixture_probe_read,0,WireMax);
    CHECK(missing.value == 0 && missing.aux == 0);
    checkRaw(board,expected);
    missing = C2(fixture_probe_read,(__bridge void *)board,WireMax);
    CHECK(missing.value == 0 && missing.aux == 0);

    NSData *nul = [NSData dataWithBytes:unicodeText length:sizeof unicodeText];
    NSData *nulWire = wire(nul,NO,NULL);
    CHECK(C3(fixture_probe_write,(__bridge void *)board,nulWire.bytes,nulWire.length).value == 1);
    Result plain = C2(mac_clip_read,(__bridge void *)board,sizeof unicodeText);
    CHECK(plain.value && plain.aux == sizeof unicodeText);
    CHECK(memcmp((void *)plain.value,unicodeText,sizeof unicodeText) == 0);
    C1(mem_free,plain.value);
    checkRaw(board,nulWire);

    NSMutableData *large = [NSMutableData dataWithLength:1 << 20];
    memset(large.mutableBytes,'x',large.length);
    NSData *largeWire = wire(large,NO,NULL);
    CHECK(C3(fixture_probe_write,(__bridge void *)board,largeWire.bytes,largeWire.length).value == 1);
    shortRead = C2(fixture_probe_read,(__bridge void *)board,largeWire.length-1);
    CHECK(shortRead.value == 0 && shortRead.aux == 0);
    checkRaw(board,largeWire);
}
static void staleTest(NSPasteboard *board) {
    writeCase(board,@"line");
    clearCache();
    uint64_t doc = document(textData(@"abc"));
    const char q = 'q';
    C5(doc_insert,doc,3,&q,1,0);
    C1(doc_undo,doc);
    CHECK([documentBytes(doc) isEqualToData:textData(@"abc")]);
    g_plat[6] = (uint64_t)fixture_hold;
    CHECK(C0(app_clip_request).value == 1);
    uint64_t token = app_clip_active_token;
    CHECK(token != 0);
    const uint64_t moved[] = {1,1}; selectPairs(doc,moved,1);
    C2(mac_clip_paste_board_tagged,(__bridge void *)board,token);
    CHECK(app_clip_active_token == 0);
    CHECK([documentBytes(doc) isEqualToData:textData(@"abc")]);
    Result selection = C2(doc_selections_get,doc,0);
    CHECK(selection.value == 1 && selection.aux == 1);
    C1(doc_redo,doc);
    CHECK([documentBytes(doc) isEqualToData:textData(@"abcq")]);
    freeDocument(doc);
    g_plat[6] = (uint64_t)fixture_private_get;
    clearCache();
}
int test_mac_clipboard_metadata(int argc, char **argv) {
    @autoreleasepool {
        g_focus = 0; cfg_vim = 0;
        g_plat[13] = (uint64_t)fixture_private_write;
        g_plat[6] = (uint64_t)fixture_private_get;
        BOOL command = argc > 1;
        if (command) {
            CHECK(argc >= 3);
            currentBoard = [NSPasteboard pasteboardWithName:[NSString stringWithUTF8String:argv[2]]];
        } else {
            currentBoard = [NSPasteboard pasteboardWithUniqueName];
        }
        CHECK(currentBoard != nil);
        test_clip_board = (__bridge void *)currentBoard;
        if (command && strcmp(argv[1],"--clear") == 0) {
            [currentBoard releaseGlobally]; return 0;
        }
        clearCache();
        uint64_t live = g_mem_live;
        if (command) {
            CHECK(argc == 4);
            NSString *kind = [NSString stringWithUTF8String:argv[3]];
            if (strcmp(argv[1],"--write") == 0) writeCase(currentBoard,kind);
            else if (strcmp(argv[1],"--read") == 0) readCase(currentBoard,kind);
            else CHECK(NO);
            return 0;              // Eager server-owned data must survive the writer's exit.
        }
        rawAndRejectionTests(currentBoard);
        CHECK(g_mem_live == live);
        for (NSString *kind in @[@"multi",@"line",@"unicode",@"empty",@"raw",@"malformed",
                                 @"version",@"native-only",@"native-first",@"native-second",@"plain"]) {
            @autoreleasepool {
                writeCase(currentBoard,kind);
                readCase(currentBoard,kind);
            }
            CHECK(g_mem_live == live);
        }
        staleTest(currentBoard);
        CHECK(g_mem_live == live);
        C0(app_clip_reset);
        [currentBoard releaseGlobally];
        puts("ok mac native clipboard metadata");
    }
    return 0;
}
