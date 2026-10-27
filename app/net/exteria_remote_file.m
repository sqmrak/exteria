#import "exteria_remote_file.h"

#import "exteria_photo.h"

enum { ExteriaRemoteProfilePhoto = 1, ExteriaRemoteMedia, ExteriaRemoteStickerSet };

@implementation ExteriaRemoteFile

@synthesize dc = _dc;
@synthesize key = _key;

+ (ExteriaRemoteFile *)fileForPhoto:(ExteriaPhoto *)photo {
    if (!photo) return nil;
    ExteriaRemoteFile *file = [[[ExteriaRemoteFile alloc] init] autorelease];
    file->_kind = ExteriaRemoteProfilePhoto;
    file->_photo = photo.ref;
    file->_dc = photo.ref.dc;
    /* the photo id is unique across telegram, so it alone names the file */
    file->_key = [[NSString stringWithFormat:@"u%lld", (long long)photo.ref.photo_id] copy];
    return file;
}

+ (ExteriaRemoteFile *)fileForMedia:(const exteria_media_ref *)ref {
    if (!ref || ref->source == EXTERIA_MEDIA_SOURCE_NONE) return nil;
    ExteriaRemoteFile *file = [[[ExteriaRemoteFile alloc] init] autorelease];
    file->_kind = ExteriaRemoteMedia;
    file->_media = *ref;
    file->_dc = ref->dc;
    /* a document and a photo can share an id, and one id has many sizes */
    file->_key = [[NSString stringWithFormat:@"%c%llx_%s", ref->source == EXTERIA_MEDIA_SOURCE_PHOTO ? 'p' : 'd',
                   (unsigned long long)ref->id, ref->thumb] copy];
    return file;
}

+ (ExteriaRemoteFile *)fileForStickerSet:(const exteria_sticker_set_row *)set {
    if (!set || set->id == 0 || set->thumb_dc <= 0) return nil;
    ExteriaRemoteFile *file = [[[ExteriaRemoteFile alloc] init] autorelease];
    file->_kind = ExteriaRemoteStickerSet;
    file->_set = *set;
    file->_dc = set->thumb_dc;
    file->_key = [[NSString stringWithFormat:@"s%llx_%d", (unsigned long long)set->id, (int)set->thumb_version] copy];
    return file;
}

- (void)dealloc {
    [_key release];
    [super dealloc];
}

- (BOOL)adoptReferenceOf:(ExteriaRemoteFile *)fresh {
    if (_kind != ExteriaRemoteMedia || fresh->_kind != ExteriaRemoteMedia || _media.source != fresh->_media.source || _media.id != fresh->_media.id ||
        strncmp(_media.thumb, fresh->_media.thumb, sizeof(_media.thumb)) != 0 || !fresh->_media.ref_len) return NO;
    memcpy(_media.file_ref, fresh->_media.file_ref, sizeof(_media.file_ref));
    _media.ref_len = fresh->_media.ref_len;
    return YES;
}

- (exteria_status)buildLocation:(exteria_arena *)arena into:(exteria_tl_value **)out {
    switch (_kind) {
    case ExteriaRemoteProfilePhoto: return exteria_photo_location(arena, &_photo, out);
    case ExteriaRemoteMedia: return exteria_media_location(arena, &_media, out);
    case ExteriaRemoteStickerSet: return exteria_sticker_set_thumb_location(arena, &_set, out);
    }
    return EXTERIA_E_ARG;
}

@end
