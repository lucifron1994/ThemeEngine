//
//  CFTAsset.m
//  carFileTool
//
//  Created by Alexander Zielenski on 8/8/14.
//  Copyright (c) 2014 Alexander Zielenski. All rights reserved.
//

#import "CFTAsset.h"
#import "CSIBitmapWrapper.h"
#import "CUIThemeGradient.h"
#import "CUIPSDGradientEvaluator.h"
#import "CUIMutableCommonAssetStorage.h"
#import <objc/runtime.h>
#import <stddef.h>
#import <CoreText/CoreText.h>
#import "CUITextEffectStack.h"
#define kSLICES 1001
#define kMETRICS 1003
#define kFLAGS 1004
#define kUTI 1005
#define kEXIF 1006
#define kRAWD 'RAWD'
#define kPDF 'PDF '

@interface CFTAsset () {
    CGImageRef _image;
}
@property (readwrite, weak) CFTElement *element;
@property (readwrite, strong) CUIThemeRendition *rendition;
@property (readwrite, strong) NSArray *slices;
@property (readwrite, strong) NSArray *metrics;
@property (readwrite, copy) NSString *name;
@property (readwrite, strong) CUIRenditionKey *key;
@property (readwrite, strong) NSSet *keywords;
@property (strong) NSPasteboard *currentPasteboard;

- (void)_initializeSlicesFromCSIData:(NSData *)csiData;
- (void)_initializeMetricsFromCSIData:(NSData *)csiData;
- (void)_initializeRawDataFromCSIData:(NSData *)csiData;
- (void)_initializeMetadataFromCSIData:(NSData *)csiData;
- (NSData *)_keyDataWithFormat:(struct _renditionkeyfmt *)format;
@end

@implementation CFTAsset
@dynamic image, pdfData, previewImage;

+ (instancetype)assetWithRenditionCSIData:(NSData *)csiData forKey:(struct _renditionkeytoken *)key {
    return [[self alloc] initWithRenditionCSIData:csiData forKey:key];
}

- (instancetype)initWithRenditionCSIData:(NSData *)csiData forKey:(struct _renditionkeytoken *)key {
    if ((self = [self init])) {
        self.key = [CUIRenditionKey renditionKeyWithKeyList:key];
        self.rendition = [[objc_getClass("CUIThemeRendition") alloc] initWithCSIData:csiData forKey:key];
        self.gradient = [CFTGradient gradientWithThemeGradient:self.rendition.gradient angle:self.rendition.gradientDrawingAngle style:self.rendition.gradientStyle];
        self.effectPreset = [CFTEffectWrapper effectWrapperWithEffectPreset:self.rendition.effectPreset];
        self.image = self.rendition.unslicedImage;
        self.type = self.rendition.type;
        self.name = self.rendition.name;
        self.utiType = self.rendition.utiType;
        self.blendMode = self.rendition.blendMode;
        self.opacity = self.rendition.opacity;
        self.exifOrientation = self.rendition.exifOrientation;

        [self _initializeMetadataFromCSIData:csiData];
        [self _initializeSlicesFromCSIData:csiData];
        [self _initializeMetricsFromCSIData:csiData];
        [self _initializeRawDataFromCSIData:csiData];
        
        NSString *name = [self.name stringByReplacingOccurrencesOfString:@"_" withString:@""];
        name = [name stringByReplacingOccurrencesOfString:@" " withString:@""];
        name = [name stringByReplacingOccurrencesOfString:@"([a-z])([A-Z])"
                                               withString:@"$1 $2"
                                                  options:NSRegularExpressionSearch
                                                    range:NSMakeRange(0, name.length)];
        self.keywords = [[NSSet setWithObjects:self.keyTypeString, self.keyStateString, self.keyLayerString, self.keyIdiomString, self.keySizeString, self.keyValueString, self.keyPresentationStateString, self.keyDirectionString, self.keyScaleString, nil] setByAddingObjectsFromArray:[name componentsSeparatedByString:@" "]];

    }
    
    return self;
}

+ (instancetype)assetWithColorDef:(struct _colordef)colordef forKey:(struct _colorkey)key {
    return [[self alloc] initWithColorDef:colordef forKey:key];
}

- (id)initWithColorDef:(struct _colordef)colordef forKey:(struct _colorkey)key {
    if ((self = [self init])) {
        
#if TARGET_OS_IPHONE
        self.color = [UIColor colorWithRed:(double)colordef.color.r / 255.0
                                     green:(double)colordef.color.g / 255.0
                                      blue:(double)colordef.color.b / 255.0
                                     alpha:(double)colordef.color.a / 255.0];
#else
        self.color = [NSColor colorWithRed:(double)colordef.color.r / 255.0
                                     green:(double)colordef.color.g / 255.0
                                      blue:(double)colordef.color.b / 255.0
                                     alpha:(double)colordef.color.a / 255.0];
#endif
        self.name = [NSString stringWithCString:key.name encoding:NSUTF8StringEncoding];
        self.type = kCoreThemeTypeColor;
        NSString *name = [self.name stringByReplacingOccurrencesOfString:@"_" withString:@""];
        name = [name stringByReplacingOccurrencesOfString:@" " withString:@""];
        name = [name stringByReplacingOccurrencesOfString:@"([a-z])([A-Z])"
                                               withString:@"$1 $2"
                                                  options:NSRegularExpressionSearch
                                                    range:NSMakeRange(0, name.length)];
        self.keywords = [NSSet setWithArray:[name componentsSeparatedByString:@" "]];
    }
    
    return self;
}

- (void)_initializeSlicesFromCSIData:(NSData *)csiData {
    unsigned int bytes = kSLICES;
    NSRange sliceLocation = [csiData rangeOfData:[NSData dataWithBytes:&bytes length:sizeof(bytes)]
                                         options:0
                                           range:NSMakeRange(0, csiData.length)];
    if (sliceLocation.location != NSNotFound) {
        unsigned int nslices = 0;
        [csiData getBytes:&nslices range:NSMakeRange(sliceLocation.location + sizeof(unsigned int) * 2, sizeof(nslices))];
        
        NSMutableArray *slices = [NSMutableArray arrayWithCapacity:nslices];
        for (int idx = 0; idx < nslices; idx++) {
            struct {
                unsigned int x;
                unsigned int y;
                unsigned int w;
                unsigned int h;
            } sliceInts;
            
            [csiData getBytes:&sliceInts range:NSMakeRange(sliceLocation.location + sizeof(sliceInts) * idx + sizeof(unsigned int) * 3, sizeof(sliceInts))];
            [slices addObject:[NSValue valueWithRect:NSMakeRect(sliceInts.x, sliceInts.y, sliceInts.w, sliceInts.h)]];
        }
        
        self.slices = slices;
    }
}

- (void)_initializeMetricsFromCSIData:(NSData *)csiData {
    unsigned int bytes = kMETRICS;
    NSRange metricLocation = [csiData rangeOfData:[NSData dataWithBytes:&bytes length:sizeof(bytes)]
                                          options:0
                                            range:NSMakeRange(0, csiData.length)];
    if (metricLocation.location != NSNotFound) {
        unsigned int nmetrics = 0;
        [csiData getBytes:&nmetrics range:NSMakeRange(metricLocation.location + sizeof(unsigned int) * 2, sizeof(nmetrics))];

        NSMutableArray *metrics = [NSMutableArray arrayWithCapacity:nmetrics];
        for (int idx = 0; idx < nmetrics; idx++) {
            CUIMetrics renditionMetric;

            struct {
                unsigned int a;
                unsigned int b;
                unsigned int c;
                unsigned int d;
                unsigned int e;
                unsigned int f;
            } mtr;
            
            [csiData getBytes:&mtr range:NSMakeRange(metricLocation.location + sizeof(mtr) * idx + sizeof(unsigned int) * 3, sizeof(mtr))];
            renditionMetric.edgeTR = CGSizeMake(mtr.c, mtr.b);
            renditionMetric.edgeBL = CGSizeMake(mtr.a, mtr.d);
            renditionMetric.imageSize = CGSizeMake(mtr.e, mtr.f);
            
            [metrics addObject:[NSValue valueWithBytes:&renditionMetric objCType:@encode(CUIMetrics)]];
        }
        
        self.metrics = metrics;
    }
}

- (void)_initializeRawDataFromCSIData:(NSData *)csiData {
    unsigned int listOffset = offsetof(struct _csiheader, infolistLength);
    unsigned int listLength = 0;
    [csiData getBytes:&listLength range:NSMakeRange(listOffset, sizeof(listLength))];
    listOffset += listLength + sizeof(unsigned int) * 4;
    
    unsigned int type = 0;
    [csiData getBytes:&type range:NSMakeRange(listOffset, sizeof(type))];
    if (type != kRAWD)
        return;
    
    listOffset += 8;
    unsigned int dataLength = 0;
    [csiData getBytes:&dataLength range:NSMakeRange(listOffset, sizeof(dataLength))];
    
    if (dataLength == 0)
        return;
    
    listOffset += sizeof(dataLength);
    self.rawData = [csiData subdataWithRange:NSMakeRange(listOffset, dataLength)];
}

- (void)_initializeMetadataFromCSIData:(NSData *)csiData {
    struct _csiheader header;
    [csiData getBytes:&header range:NSMakeRange(0, offsetof(struct _csiheader, infolistLength) + sizeof(unsigned int))];
    
    self.renditionFPO = header.renditionFlags.isHeaderFlaggedFPO;
    self.excludedFromContrastFilter = header.renditionFlags.isExcludedFromContrastFilter;
    self.vector = header.renditionFlags.isVectorBased;
    self.opaque = header.renditionFlags.isOpaque;
    
    self.layout = header.metadata.layout;
    self.scale  = (CGFloat)header.scaleFactor / 100.0;
    self.colorSpaceID = (short)header.colorspaceID;
}

// same as calling CUIStructuredThemeStore _newRenditionKeyDataFromKey:
- (NSData *)_keyDataWithFormat:(struct _renditionkeyfmt *)format {
    /*
     The key format contains a list of the order of attributes for which they should appear
     for each key in data. The list has just ints corresponding to the identifier for each attribute
     so we find which index each value in the attribute list shall go into and place its value at the
     right offset. Identifiers correspond to CFTThemeAttributeName
     */
    NSMutableData *data = [[NSMutableData alloc] initWithLength:format->numTokens * sizeof(uint16_t)];
    struct _renditionkeytoken currentToken = self.key.keyList[0];
    unsigned int idx = 0;
    do {
        int tokenIdx = -1;
        unsigned int keyIdx = 0;
        do {
            if (format->attributes[keyIdx] == currentToken.identifier)
                tokenIdx = keyIdx;
            keyIdx++;
        } while (tokenIdx == -1 && keyIdx < format->numTokens);
        
        if (tokenIdx != -1) {
            size_t size = sizeof(currentToken.value);
            [data replaceBytesInRange:NSMakeRange(tokenIdx * size, size) withBytes:&currentToken.value length:size];
        }
        
        currentToken = self.key.keyList[++idx];
    } while (currentToken.identifier != 0);
    
    return data;
}

- (void)commitToStorage:(CUIMutableCommonAssetStorage *)assetStorage {
    if (self.type == kCoreThemeTypeColor) {
        struct _rgbquad quad;
        quad.r = (uint8_t)(self.color.redComponent * 255);
        quad.g = (uint8_t)(self.color.greenComponent * 255);
        quad.b = (uint8_t)(self.color.blueComponent * 255);
        quad.a = (uint8_t)(self.color.alphaComponent * 255);
        
        [assetStorage setColor:quad
                       forName:self.name.UTF8String
             excludeFromFilter:NO];
        
        return;
    }
    NSData *renditionKey = [self _keyDataWithFormat:(struct _renditionkeyfmt *)assetStorage.keyFormat];

    if (self.shouldRemove) {
        [assetStorage removeAssetForKey:renditionKey];
        return;
    }
    
    if (!self.isDirty)
        return;
    
    if (self.type > kCoreThemeTypePDF) {
        // we only save shape effects, gradients, pdfs, and bitmaps
        return;
    }
    
    CUIShapeEffectPreset *effectPreset = self.effectPreset.effectPreset;
    CSIGenerator *gen = nil;
    if (self.type == kCoreThemeTypeEffect) {
        gen = [[CSIGenerator alloc] initWithShapeEffectPreset:effectPreset forScaleFactor:self.scale];
    } else if (self.type == kCoreThemeTypePDF) {
        gen = [[CSIGenerator alloc] initWithRawData:self.pdfData pixelFormat:kPDF layout:self.layout];
    } else {
        CGSize size = CGSizeZero;
        if (self.type != kCoreThemeTypeGradient) {
            size = CGSizeMake(CGImageGetWidth(self.image), CGImageGetHeight(self.image));
        }
        gen = [[CSIGenerator alloc] initWithCanvasSize:size sliceCount:(unsigned int)self.slices.count layout:self.layout];
    }
    
    if (self.image) {
        CGSize imageSize = CGSizeMake(CGImageGetWidth(self.image), CGImageGetHeight(self.image));
        CSIBitmapWrapper *wrapper = [[CSIBitmapWrapper alloc] initWithPixelWidth:imageSize.width
                                                                     pixelHeight:imageSize.height];
        CGContextDrawImage(wrapper.bitmapContext, CGRectMake(0, 0, imageSize.width, imageSize.height), self.image);
        [gen addBitmap:wrapper];
    }
    
    
    for (unsigned int idx = 0; idx < self.slices.count; idx++) {
        [gen addSliceRect:[self.slices[idx] rectValue]];
    }
    
    for (unsigned int idx = 0; idx < self.metrics.count; idx++) {
        CUIMetrics metrics;
        [self.metrics[idx] getValue:&metrics];
        [gen addMetrics:metrics];
    }

    gen.gradient = [self.gradient valueForKey:@"psdGradient"];
    gen.effectPreset = effectPreset;
    if (self.type <= 8) {
        gen.scaleFactor = self.scale;
    }
    
//!TODO: For some reason whenever I compile PDFs i get a colorspaceID of 15 even when I set it to something else
    gen.exifOrientation = self.exifOrientation;
    gen.colorSpaceID = self.colorSpaceID;
    gen.opacity = self.opacity;
    gen.blendMode = self.blendMode;
    gen.templateRenderingMode = self.rendition.templateRenderingMode;
    gen.isVectorBased = self.isVector;
    gen.utiType = self.utiType;
    gen.isRenditionFPO = self.isRenditionFPO;
    gen.name = self.rendition.name;
//    gen.excludedFromContrastFilter = YES;
    NSData *csiData = [gen CSIRepresentationWithCompression:YES];
    [assetStorage setAsset:csiData forKey:renditionKey];
}

- (BOOL)isDirty {
    BOOL clean = YES;
#define COMPARE(KEY) clean &= self.KEY == self.rendition.KEY
    COMPARE(scale);
    COMPARE(exifOrientation);
    COMPARE(opacity);
    COMPARE(blendMode);
    COMPARE(colorSpaceID);
    COMPARE(utiType);
    COMPARE(type);
    
    clean &= self.layout == self.rendition.subtype;
    clean &= self.image == self.rendition.unslicedImage;
    clean &= [self.gradient isEqualToThemeGradient:self.rendition.gradient];

    //!TODO: Make this better
    if (self.type == kCoreThemeTypeColor)
        return YES;
    //!TODO: Shape Effect
    
    //!TODO: PDF Data
    //!TODO: slice changes
    
    return !clean;
}

#pragma mark - Properties

- (CGImageRef)image {
    @synchronized(self) {
        return _image;
    }
}

- (void)setImage:(CGImageRef)image {
    @synchronized(self) {
        if (_image != NULL)
            CGImageRelease(_image);
        
        _image = CGImageRetain(image);
    }
}

- (NSData *)pdfData {
    return self.rawData;
}

- (void)setPdfData:(NSData *)pdfData {
    [self setRawData:pdfData];
}

+ (NSSet *)keyPathsForValuesAffectingPdfData {
    return [NSSet setWithObject:@"rawData"];
}


//!TODO: Generate gradient and effect previews
#if TARGET_OS_IPHONE
- (UIImage *)previewImage {
    return [UIImage imageWithCGImage:self.image];
}
#else
- (NSImage *)previewImage {
    NSImage *image = [[NSImage alloc] init];
    if (self.image) {
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:self.image];
        [image addRepresentation:rep];
    } else if (self.type == kCoreThemeTypePDF) {
        NSPDFImageRep *rep = [[NSPDFImageRep alloc] initWithData:self.pdfData];
        [image addRepresentation:rep];
    } else if (self.type == kCoreThemeTypeGradient) {
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                        pixelsWide:40
                                                                        pixelsHigh:40
                                                                     bitsPerSample:8
                                                                   samplesPerPixel:4
                                                                          hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSDeviceRGBColorSpace
                                                                       bytesPerRow:4 * 40
                                                                      bitsPerPixel:32];
        NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        CUIThemeGradient *grad = self.gradient.themeGradientRepresentation;
        if (self.gradient.isRadial) {
            [grad drawFromPoint:CGPointMake(rep.pixelsWide / 2, rep.pixelsHigh / 2) toPoint:CGPointZero
                        options:0
                    withContext:ctx.graphicsPort];
        } else {
            [grad drawInRect:CGRectMake(0, 0, rep.pixelsWide, rep.pixelsHigh) angle:self.gradient.angle withContext:ctx.graphicsPort];
        }
        
        [image addRepresentation:rep];
        
    } else if (self.type == kCoreThemeTypeEffect) {
        //!TODO: Don't use coretext
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                        pixelsWide:32
                                                                        pixelsHigh:32
                                                                     bitsPerSample:8
                                                                   samplesPerPixel:4
                                                                          hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSDeviceRGBColorSpace
                                                                       bytesPerRow:4 * 32
                                                                      bitsPerPixel:32];
        NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        
        unichar chars[2] = { 0x41, 0x61 };
        CGGlyph glyphs[2];
        CGPoint positions[2];
        CGSize advances[2];
        
        CTFontRef font = CTFontCreateWithName(CFSTR("HelveticaNeue-Medium"), 18.0, NULL);
        CTFontGetGlyphsForCharacters(font, chars, glyphs, 2);
        CTFontGetAdvancesForGlyphs(font, kCTFontDefaultOrientation, glyphs, advances, 2);
        
        CGPoint position = CGPointZero;
        for (NSUInteger i = 0; i < 2; i++) {
            positions[i] = CGPointMake(position.x, position.y);
            CGSize advance = advances[i];
            position.x += advance.width;
            position.y += advance.height;
        }
        
        positions[0].x += rep.pixelsWide / 2 - position.x / 2;
        positions[0].y += rep.pixelsHigh / 2 - position.y / 2 - 6;
        positions[1].x += rep.pixelsWide / 2 - position.x / 2;
        positions[1].y += rep.pixelsHigh / 2 - position.y / 2 - 6;

        CUITextEffectStack *stack = [[CUITextEffectStack alloc] initWithEffectPreset:self.effectPreset.effectPreset];
        CTFontDrawGlyphs(font, glyphs, positions, 2, ctx.graphicsPort);

        [image addRepresentation:[[NSBitmapImageRep alloc] initWithCGImage:[stack newFlattenedImageFromShapeCGImage:rep.CGImage]]];
    } else if (self.type == kCoreThemeTypeColor) {
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                        pixelsWide:40
                                                                        pixelsHigh:40
                                                                     bitsPerSample:8
                                                                   samplesPerPixel:4
                                                                          hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSDeviceRGBColorSpace
                                                                       bytesPerRow:4 * 40
                                                                      bitsPerPixel:32];
        NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        CGContextSetFillColorWithColor(ctx.graphicsPort, self.color.CGColor);
        CGContextFillRect(ctx.graphicsPort, CGRectMake(0, 0, rep.pixelsWide, rep.pixelsHigh));
        
        [image addRepresentation:rep];
    } else {
        image = [NSImage imageNamed:@"NSApplicationIcon"];
    }

    return image;
}
#endif

+ (NSSet *)keyPathsForValuesAffectingPreviewImage {
    return [NSSet setWithObjects:@"image", @"pdfData", @"gradient", @"effectPreset", nil];
}

- (NSString *)debugDescription {
    if (self.type != kCoreThemeTypeColor) {
        return [NSString stringWithFormat:@"%@: Type: %@, State: %@, Scale: %lld, Layer: %@, Idiom: %@, Size: %@, Value: %@, Presentation: %@, Dimension1: %@, Direction: %@", self.name, self.keyTypeString, self.keyStateString, self.key.themeScale, self.keyLayerString, self.keyIdiomString, self.keySizeString, self.keyValueString, self.keyPresentationStateString, self.keyDimension1String, self.keyDirectionString];
    }
    
    return [NSString stringWithFormat:@"%@: {r: %d, g: %d, b: %d, a: %d}", self.name, (uint32_t)(self.color.redComponent * 255), (uint32_t)(self.color.greenComponent * 255), (uint32_t)(self.color.blueComponent * 255), (uint32_t)(self.color.alphaComponent * 255)];
}

- (NSString *)keyTypeString {
    return CoreThemeTypeToString(self.type);
}

- (NSString *)keyStateString {
    return CoreThemeStateToString(self.key.themeState);
}

- (NSString *)keyScaleString {
    return CFTScaleToString(self.key.themeScale);
}

- (NSString *)keyLayerString {
    return CoreThemeLayerToString(self.key.themeLayer);
}

- (NSString *)keyIdiomString {
    return CoreThemeIdiomToString(self.key.themeIdiom);
}

- (NSString *)keySizeString {
    return CoreThemeSizeToString(self.key.themeSize);
}

- (NSString *)keyValueString {
    return CoreThemeValueToString(self.key.themeValue);
}

- (NSString *)keyPresentationStateString {
    return CoreThemePresentationStateToString(self.key.themePresentationState);
}

- (NSString *)keyDirectionString {
    return CoreThemeDirectionToString(self.key.themeDirection);
}

- (NSString *)keyDimension1String {
    return [@(self.key.themeDimension1) stringValue];
}

- (NSString *)keyDimension2String {
    return [@(self.key.themeDimension2) stringValue];
}

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
    if ([key hasPrefix:@"key"] && [key hasSuffix:@"String"]) {
        return [NSSet setWithObjects:@"key", nil];
    }
    return [super keyPathsForValuesAffectingValueForKey:key];
}

#pragma mark - NSPasteboardWriting

- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard {
    self.currentPasteboard = pasteboard;
    if (self.type > kCoreThemeTypePDF)
        return @[];
    //!TODO: Color
    return @[ self.type == kCoreThemeTypePDF ? NSPasteboardTypePDF : NSPasteboardTypePNG, (__bridge NSString *)kPasteboardTypeFilePromiseContent, (__bridge NSString *)kUTTypeFileURL ];
}

- (NSPasteboardWritingOptions)writingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard {
    return NSPasteboardWritingPromised;
}

- (id)pasteboardPropertyListForType:(NSString *)type {
    if ([type isEqualToString:NSPasteboardTypePDF])
        return self.pdfData;
    else if ([type isEqualToString:NSPasteboardTypePNG])
        return [self.previewImage.representations[0] representationUsingType:NSPNGFileType properties:nil];
    else if ([type isEqualToString:(__bridge NSString *)kPasteboardTypeFilePromiseContent]) {
        return self.type == kCoreThemeTypePDF ? (__bridge NSString *)kUTTypePDF : (__bridge NSString *)kUTTypePNG;
    }

    NSURL *finalURL = [NSURL URLWithString:[[[[NSUUID UUID] UUIDString] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] stringByAppendingPathExtension:self.type == kCoreThemeTypePDF ? @"pdf" : @"png"] relativeToURL:[NSURL fileURLWithPath:NSTemporaryDirectory()]];
    
    if (self.type == kCoreThemeTypePDF)
        [self.pdfData writeToURL:finalURL atomically:NO];
    else
        [[self.previewImage.representations[0] representationUsingType:NSPNGFileType properties:nil] writeToURL:finalURL atomically:NO];
    
    
    // Write your file to finalURL here
    
    return [finalURL absoluteString];
}

@end

@interface CUIShapeEffectPreset (Copying) <NSCopying>
@end

@implementation CUIShapeEffectPreset (Copying)

- (id)copyWithZone:(NSZone *)zone {
    CUIShapeEffectPreset *preset = [[CUIShapeEffectPreset allocWithZone:zone] initWithEffectScale:self.effectScale];
    for (NSUInteger x = 0; x < self.effectCount; x++) {
        CUIEffectTuple *tuples = NULL;
        unsigned long long ntuples = 0;
        [self getEffectTuples:&tuples count:&ntuples atEffectIndex:0];
        
        for (unsigned long long y = 0; x < ntuples; y++)
            [preset _insertEffectTuple:tuples[y] atEffectIndex:x];
        
    }
    
    return preset;
}

@end