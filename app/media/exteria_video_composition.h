#import <AVFoundation/AVFoundation.h>

/* applies the source orientation, then quarter turns and an optional horizontal mirror, then the crop: a rectangle of any shape given as fractions of the picture as it stands after
   the turns (x, y, width, height); an empty one keeps the whole picture */
AVVideoComposition *ExteriaVideoComposition(AVAsset *asset, NSInteger turns, BOOL mirror, CGRect crop);

/* the asset itself when it has a sound track; otherwise a composition of its picture and a track of silence as long as it. telegram shows a video without a sound track as a gif
   (the bot api calls an animation "a video without sound"), and a screen recording or a clip with its sound taken away at the source must stay a video. the asset itself, with the
   reason logged, when the silence cannot be made, so the video still goes out as it is */
AVAsset *ExteriaAssetWithSoundTrack(AVAsset *asset);
