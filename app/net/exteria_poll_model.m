#import "exteria_poll_model.h"

static NSString *ExteriaPollText(const char *bytes) {
    NSString *text = bytes ? [NSString stringWithUTF8String:bytes] : nil;
    return text ? text : @"";
}

@implementation ExteriaPollAnswer
@synthesize text = _text;
@synthesize option = _option;
@synthesize voters = _voters;
@synthesize chosen = _chosen;
@synthesize correct = _correct;

- (id)initWithRow:(const exteria_poll_answer *)row {
    self = [super init];
    if (!self) return nil;
    _text = [ExteriaPollText(row->text) copy];
    _option = [[NSData alloc] initWithBytes:row->option length:row->option_len];
    _voters = row->voters;
    _chosen = row->chosen != 0;
    _correct = row->correct != 0;
    return self;
}

- (void)dealloc {
    [_text release];
    [_option release];
    [super dealloc];
}
@end

@implementation ExteriaPoll
@synthesize question = _question;
@synthesize answers = _answers;
@synthesize pollId = _pollId;
@synthesize closed = _closed;
@synthesize publicVoters = _publicVoters;
@synthesize multiple = _multiple;
@synthesize quiz = _quiz;
@synthesize revotingDisabled = _revotingDisabled;
@synthesize hideResults = _hideResults;
@synthesize totalVoters = _totalVoters;
@synthesize recentVoters = _recentVoters;
@synthesize hasCounts = _hasCounts;
@synthesize picked = _picked;

+ (ExteriaPoll *)pollWithRow:(const exteria_poll *)row {
    if (!row->present) return nil;
    ExteriaPoll *poll = [[[ExteriaPoll alloc] init] autorelease];
    poll->_question = [ExteriaPollText(row->question) copy];
    NSMutableArray *answers = [NSMutableArray arrayWithCapacity:row->answer_count];
    for (uint8_t i = 0; i < row->answer_count; ++i) [answers addObject:[[[ExteriaPollAnswer alloc] initWithRow:&row->answers[i]] autorelease]];
    poll->_answers = [answers copy];
    poll->_pollId = row->id;
    poll->_closed = row->closed != 0;
    poll->_publicVoters = row->public_voters != 0;
    poll->_multiple = row->multiple != 0;
    poll->_quiz = row->quiz != 0;
    poll->_revotingDisabled = row->revoting_disabled != 0;
    poll->_hideResults = row->hide_results != 0;
    poll->_hasCounts = row->has_counts != 0;
    poll->_totalVoters = row->total_voters;
    NSMutableArray *recent = [NSMutableArray arrayWithCapacity:row->recent_voter_count];
    for (uint8_t i = 0; i < row->recent_voter_count; ++i) [recent addObject:[NSNumber numberWithLongLong:row->recent_voters[i]]];
    poll->_recentVoters = [recent copy];
    poll->_picked = [[NSMutableIndexSet alloc] init];
    return poll;
}

- (void)dealloc {
    [_question release];
    [_answers release];
    [_recentVoters release];
    [_picked release];
    [super dealloc];
}

- (BOOL)voted {
    for (ExteriaPollAnswer *answer in _answers) if (answer.chosen) return YES;
    return NO;
}

- (void)togglePicked:(NSUInteger)index {
    if (index >= _answers.count) return;
    if ([_picked containsIndex:index]) [_picked removeIndex:index];
    else [_picked addIndex:index];
}

- (void)clearPicked {
    [_picked removeAllIndexes];
}

- (void)inheritPickedFrom:(ExteriaPoll *)older {
    if (!older || older.pollId != _pollId || self.voted || _closed || older.picked.count == 0) return;
    NSUInteger count = _answers.count;
    NSMutableIndexSet *picked = _picked;
    [older.picked enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        (void)stop;
        if (index < count) [picked addIndex:index];
    }];
}

- (NSString *)stateKey {
    NSMutableString *key = [NSMutableString stringWithFormat:@"%lld:%d%d:%d:", _pollId, _closed, self.voted, (int)_totalVoters];
    for (ExteriaPollAnswer *answer in _answers) [key appendFormat:@"%d%d%d;", (int)answer.voters, answer.chosen, answer.correct];
    for (NSNumber *voter in _recentVoters) [key appendFormat:@"v%lld", voter.longLongValue];
    [_picked enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) { (void)stop; [key appendFormat:@"p%lu", (unsigned long)index]; }];
    return key;
}

- (BOOL)showsResultsEarly:(BOOL)early {
    if (_closed || self.voted) return YES;
    return early && _hasCounts && !_hideResults;
}
@end
