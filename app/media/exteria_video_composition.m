#import "exteria_video_composition.h"
#include "exteria_video_edit.h"

AVVideoComposition *ExteriaVideoComposition(AVAsset *asset, NSInteger turns, BOOL mirror, CGRect crop) {
    if (!asset || turns < 0 || turns > 3) return nil;
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (!tracks.count) return nil;
    AVAssetTrack *track = [tracks objectAtIndex:0];
    CGSize natural = track.naturalSize;
    if (!isfinite(natural.width) || !isfinite(natural.height) || natural.width <= 0 || natural.height <= 0) return nil;
    CGAffineTransform place = track.preferredTransform;
    CGRect bounds = CGRectStandardize(CGRectApplyAffineTransform(CGRectMake(0, 0, natural.width, natural.height), place));
    if (!isfinite(bounds.size.width) || !isfinite(bounds.size.height) || bounds.size.width < 1 || bounds.size.height < 1 ||
        bounds.size.width > 4096 || bounds.size.height > 4096) return nil;
    place = CGAffineTransformConcat(place, CGAffineTransformMakeTranslation(-bounds.origin.x, -bounds.origin.y));
    CGFloat width = bounds.size.width, height = bounds.size.height;
    for (NSInteger i = 0; i < turns; ++i) {
        place = CGAffineTransformConcat(place, CGAffineTransformMake(0, 1, -1, 0, height, 0));
        CGFloat previous = width; width = height; height = previous;
    }
    if (mirror) place = CGAffineTransformConcat(place, CGAffineTransformMake(-1, 0, 0, 1, width, 0));
    double x = 0, y = 0, cropWidth = 0, cropHeight = 0;
    exteria_status cropped = CGRectIsEmpty(crop) ? exteria_video_edit_crop(width, height, 0, &x, &y, &cropWidth, &cropHeight)
                                                  : exteria_video_edit_crop_rect(width, height, crop.origin.x, crop.origin.y, crop.size.width, crop.size.height, &x, &y, &cropWidth, &cropHeight);
    if (cropped != EXTERIA_OK) return nil;
    place = CGAffineTransformConcat(place, CGAffineTransformMakeTranslation(-x, -y));
    AVMutableVideoCompositionLayerInstruction *layer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
    [layer setTransform:place atTime:kCMTimeZero];
    AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);
    instruction.layerInstructions = [NSArray arrayWithObject:layer];
    AVMutableVideoComposition *composition = [AVMutableVideoComposition videoComposition];
    composition.renderSize = CGSizeMake(floor(cropWidth / 2) * 2, floor(cropHeight / 2) * 2);
    float fps = track.nominalFrameRate;
    if (!isfinite(fps) || fps < 1 || fps > 60) fps = 30;
    composition.frameDuration = CMTimeMake(1, (int32_t)lrintf(fps));
    composition.instructions = [NSArray arrayWithObject:instruction];
    return composition;
}

#import <AudioToolbox/AudioToolbox.h>

#define SILENCE_SECONDS 10
#define SILENCE_RATE 44100
#define SILENCE_INSERTS_MAX 9000

/* ten seconds of 16 bit mono zeros in a file of the temporary directory, written once; the exporter turns it into aac with the rest */
static NSURL *ExteriaSilenceFile(void) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"exteria-silence.caf"];
    NSURL *url = [NSURL fileURLWithPath:path];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    const UInt32 bytes = SILENCE_SECONDS * SILENCE_RATE * 2;
    if ([[attributes objectForKey:NSFileSize] unsignedLongLongValue] > bytes) return url;
    AudioStreamBasicDescription format;
    memset(&format, 0, sizeof(format));
    format.mSampleRate = SILENCE_RATE;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    format.mBitsPerChannel = 16;
    format.mChannelsPerFrame = 1;
    format.mBytesPerFrame = 2;
    format.mFramesPerPacket = 1;
    format.mBytesPerPacket = 2;
    AudioFileID file = NULL;
    OSStatus status = AudioFileCreateWithURL((CFURLRef)url, kAudioFileCAFType, &format, kAudioFileFlags_EraseFile, &file);
    if (status != noErr) { NSLog(@"exteria: the silent track was not created: %d", (int)status); return nil; }
    void *zeros = calloc(1, bytes);
    UInt32 written = bytes;
    status = zeros ? AudioFileWriteBytes(file, false, 0, &written, zeros) : kAudioFileUnspecifiedError;
    free(zeros);
    AudioFileClose(file);
    if (status != noErr || written != bytes) {
        NSLog(@"exteria: the silent track was not written: %d", (int)status);
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        return nil;
    }
    return url;
}

AVAsset *ExteriaAssetWithSoundTrack(AVAsset *asset) {
    if (!asset || [asset tracksWithMediaType:AVMediaTypeAudio].count) return asset;
    NSArray *videos = [asset tracksWithMediaType:AVMediaTypeVideo];
    double seconds = CMTimeGetSeconds(asset.duration);
    if (!videos.count || !isfinite(seconds) || seconds <= 0 || seconds / SILENCE_SECONDS > SILENCE_INSERTS_MAX) return asset;
    NSURL *silence = ExteriaSilenceFile();
    NSArray *quietTracks = silence ? [[AVURLAsset URLAssetWithURL:silence options:nil] tracksWithMediaType:AVMediaTypeAudio] : nil;
    /* firstObject is ios 7 and later */
    AVAssetTrack *quiet = quietTracks.count ? [quietTracks objectAtIndex:0] : nil;
    if (!quiet) { NSLog(@"exteria: the silent track could not be read"); return asset; }
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVAssetTrack *source = [videos objectAtIndex:0];
    AVMutableCompositionTrack *picture = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    NSError *error = nil;
    if (!picture || ![picture insertTimeRange:CMTimeRangeMake(kCMTimeZero, asset.duration) ofTrack:source atTime:kCMTimeZero error:&error]) {
        NSLog(@"exteria: the picture was not copied for the silent track: %@", error);
        return asset;
    }
    picture.preferredTransform = source.preferredTransform;
    AVMutableCompositionTrack *sound = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    CMTime at = kCMTimeZero;
    while (sound && CMTimeCompare(at, asset.duration) < 0) {
        CMTime left = CMTimeSubtract(asset.duration, at);
        CMTime piece = CMTimeMinimum(left, CMTimeMake(SILENCE_SECONDS, 1));
        if (![sound insertTimeRange:CMTimeRangeMake(kCMTimeZero, piece) ofTrack:quiet atTime:at error:&error]) {
            NSLog(@"exteria: the silent track was not laid: %@", error);
            return asset;
        }
        at = CMTimeAdd(at, piece);
    }
    return sound ? composition : asset;
}
