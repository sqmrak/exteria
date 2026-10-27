#import "exteria_time.h"

#import <UIKit/UIKit.h>

#import "exteria_chat_settings.h"
#import "exteria_language.h"

#include "exteria_people.h"

NSString *const ExteriaTimeDidChangeNotification = @"ExteriaTimeDidChange";
static NSString *const ExteriaTimeZoneKey = @"exteria.timeZoneMinutes";
static NSMutableDictionary *sFormatters;
static BOOL sBoundsStale = YES;

int32_t ExteriaTimeZoneChoice(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:ExteriaTimeZoneKey];
    if (![value isKindOfClass:[NSNumber class]]) return EXTERIA_TIME_ZONE_AUTO;
    long long minutes = [value longLongValue];
    if (minutes < INT32_MIN || minutes > INT32_MAX || !exteria_time_zone_valid((int32_t)minutes)) return EXTERIA_TIME_ZONE_AUTO;
    return (int32_t)minutes;
}

static NSTimeZone *ExteriaDisplayTimeZone(void) {
    int32_t minutes = ExteriaTimeZoneChoice();
    return minutes == EXTERIA_TIME_ZONE_AUTO ? [NSTimeZone systemTimeZone] : [NSTimeZone timeZoneForSecondsFromGMT:minutes * 60];
}

static void ExteriaTimeChanged(void) {
    [sFormatters removeAllObjects];
    sBoundsStale = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaTimeDidChangeNotification object:nil];
}

static void ExteriaObserveTime(void) {
    static BOOL observing;
    if (observing) return;
    observing = YES;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    void (^changed)(NSNotification *) = ^(NSNotification *note) {
        (void)note;
        [NSTimeZone resetSystemTimeZone];
        ExteriaTimeChanged();
    };
    for (NSString *name in [NSArray arrayWithObjects:NSSystemTimeZoneDidChangeNotification, NSSystemClockDidChangeNotification,
                           NSCurrentLocaleDidChangeNotification, UIApplicationDidBecomeActiveNotification, nil])
        [center addObserverForName:name object:nil queue:[NSOperationQueue mainQueue] usingBlock:changed];
}

void ExteriaTimeZoneSetChoice(int32_t minutes) {
    if (!exteria_time_zone_valid(minutes)) {
        NSLog(@"exteria: invalid display time zone offset %d", (int)minutes);
        return;
    }
    ExteriaObserveTime();
    if (minutes == ExteriaTimeZoneChoice()) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (minutes == EXTERIA_TIME_ZONE_AUTO) [defaults removeObjectForKey:ExteriaTimeZoneKey];
    else [defaults setObject:[NSNumber numberWithInt:minutes] forKey:ExteriaTimeZoneKey];
    ExteriaTimeChanged();
}

NSString *ExteriaTimeZoneOffsetText(int32_t minutes) {
    if (minutes == EXTERIA_TIME_ZONE_AUTO || !exteria_time_zone_valid(minutes)) return NSLocalizedString(@"time.zone.auto", nil);
    int magnitude = minutes < 0 ? -(int)minutes : (int)minutes;
    return [NSString stringWithFormat:@"UTC%c%02d:%02d", minutes < 0 ? '-' : '+', magnitude / 60, magnitude % 60];
}

NSString *ExteriaTimeZoneChoiceText(void) {
    return ExteriaTimeZoneOffsetText(ExteriaTimeZoneChoice());
}

NSCalendar *ExteriaDisplayCalendar(void) {
    ExteriaObserveTime();
    NSCalendar *calendar = [[[NSCalendar currentCalendar] copy] autorelease];
    [calendar setTimeZone:ExteriaDisplayTimeZone()];
    return calendar;
}

static NSDateFormatter *ExteriaFormatter(NSString *template, NSDateFormatterStyle dateStyle) {
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setLocale:ExteriaFormattingLocale()];
    [formatter setTimeZone:ExteriaDisplayTimeZone()];
    if (template) {
        [formatter setDateFormat:[NSDateFormatter dateFormatFromTemplate:template options:0 locale:ExteriaFormattingLocale()]];
    } else {
        [formatter setDateStyle:dateStyle];
        [formatter setTimeStyle:NSDateFormatterNoStyle];
    }
    return formatter;
}

/* time and locale notifications discard formatters that captured the old display settings */
static NSDateFormatter *ExteriaCachedFormatter(NSString *key, NSString *template, NSDateFormatterStyle dateStyle) {
    ExteriaObserveTime();
    if (!sFormatters) sFormatters = [[NSMutableDictionary alloc] init];
    NSString *full = [key stringByAppendingString:[ExteriaFormattingLocale() localeIdentifier]];
    NSDateFormatter *formatter = [sFormatters objectForKey:full];
    if (!formatter) {
        formatter = ExteriaFormatter(template, dateStyle);
        [sFormatters setObject:formatter forKey:full];
    }
    return formatter;
}

static NSDate *sToday = nil;
static NSDate *sYesterday = nil;
static NSDate *sWeekEdge = nil;
static NSDate *sNextMidnight = nil;

static void ExteriaStoreBound(NSDate **slot, NSDate *value) {
    [value retain];
    [*slot release];
    *slot = value;
}

static NSDate *ExteriaDayShifted(NSCalendar *calendar, NSDate *from, NSInteger days) {
    NSDateComponents *shift = [[[NSDateComponents alloc] init] autorelease];
    [shift setDay:days];
    return [calendar dateByAddingComponents:shift toDate:from options:0];
}

/* the day edges come from the calendar because a day is 23 or 25 hours long on a daylight saving switch, and they
   are kept until the stored next midnight */
static void ExteriaRefreshDayBounds(void) {
    ExteriaObserveTime();
    NSDate *now = [NSDate date];
    if (!sBoundsStale && sToday && [now compare:sToday] != NSOrderedAscending && [now compare:sNextMidnight] == NSOrderedAscending) return;
    NSCalendar *calendar = ExteriaDisplayCalendar();
    NSDateComponents *parts = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:now];
    NSDate *today = [calendar dateFromComponents:parts];
    ExteriaStoreBound(&sToday, today);
    ExteriaStoreBound(&sYesterday, ExteriaDayShifted(calendar, today, -1));
    ExteriaStoreBound(&sWeekEdge, ExteriaDayShifted(calendar, today, -6));
    ExteriaStoreBound(&sNextMidnight, ExteriaDayShifted(calendar, today, 1));
    sBoundsStale = NO;
}

NSString *ExteriaListTimeText(int32_t unixDate) {
    if (unixDate <= 0) return @"";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:unixDate];
    ExteriaRefreshDayBounds();
    if ([date compare:sToday] != NSOrderedAscending) return [ExteriaCachedFormatter(@"clock", @"jmm", NSDateFormatterNoStyle) stringFromDate:date];
    if ([date compare:sWeekEdge] == NSOrderedDescending) return [ExteriaCachedFormatter(@"weekday", @"EEE", NSDateFormatterNoStyle) stringFromDate:date];
    return [ExteriaCachedFormatter(@"short", nil, NSDateFormatterShortStyle) stringFromDate:date];
}

NSString *ExteriaDayText(int32_t unixDate) {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:unixDate];
    ExteriaRefreshDayBounds();
    if ([date compare:sToday] != NSOrderedAscending) return NSLocalizedString(@"chat.today", nil);
    if ([date compare:sYesterday] != NSOrderedAscending) return NSLocalizedString(@"chat.yesterday", nil);
    if ([date compare:sWeekEdge] == NSOrderedDescending) return [ExteriaCachedFormatter(@"weekdayfull", @"EEEE", NSDateFormatterNoStyle) stringFromDate:date];
    return [ExteriaCachedFormatter(@"day", @"dMMMMyyyy", NSDateFormatterNoStyle) stringFromDate:date];
}

NSString *ExteriaLastSeenText(int presence, int32_t seen) {
    switch ((exteria_presence)presence) {
    case EXTERIA_PRESENCE_ONLINE:
        return NSLocalizedString(@"seen.online", nil);
    case EXTERIA_PRESENCE_OFFLINE: {
        if (seen <= 0) break;
        if (ExteriaChatFlagGet(ExteriaChatFlagRelativeSeen)) {
            /* a time in the future (a clock that runs ahead of the server) has no age, so it reads as the exact time */
            NSTimeInterval age = [[NSDate date] timeIntervalSince1970] - seen;
            if (age >= 0 && age < 60) return NSLocalizedString(@"seen.ago.now", nil);
            if (age >= 60 && age < 3600) return [NSString stringWithFormat:NSLocalizedString(@"seen.ago.minutes", nil), (int)(age / 60)];
            if (age >= 3600 && age < 86400) return [NSString stringWithFormat:NSLocalizedString(@"seen.ago.hours", nil), (int)(age / 3600)];
        }
        return [NSString stringWithFormat:NSLocalizedString(@"seen.at", nil), ExteriaListTimeText(seen)];
    }
    case EXTERIA_PRESENCE_RECENTLY:
        return NSLocalizedString(@"seen.recently", nil);
    case EXTERIA_PRESENCE_LAST_WEEK:
        return NSLocalizedString(@"seen.week", nil);
    case EXTERIA_PRESENCE_LAST_MONTH:
        return NSLocalizedString(@"seen.month", nil);
    case EXTERIA_PRESENCE_DELETED:
        return NSLocalizedString(@"seen.deleted", nil);
    case EXTERIA_PRESENCE_UNKNOWN:
        break;
    }
    return NSLocalizedString(@"seen.long", nil);
}

NSString *ExteriaMediaTimeText(int32_t unixDate) {
    if (unixDate <= 0) return @"";
    NSString *day = ExteriaDayText(unixDate);
    if ([day isEqualToString:NSLocalizedString(@"chat.today", nil)] || [day isEqualToString:NSLocalizedString(@"chat.yesterday", nil)]) day = day.lowercaseString;
    NSString *clock = [ExteriaCachedFormatter(@"clock", @"jmm", NSDateFormatterNoStyle) stringFromDate:[NSDate dateWithTimeIntervalSince1970:unixDate]];
    return [NSString stringWithFormat:NSLocalizedString(@"media.date", nil), day, clock];
}

/* the clock of a message follows the 12 or 24 hour choice of the system like the times of the list do */
NSString *ExteriaClockText(int32_t unixDate) {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:unixDate];
    if (ExteriaChatFlagGet(ExteriaChatFlagSeconds)) return [ExteriaCachedFormatter(@"clockseconds", @"jmmss", NSDateFormatterNoStyle) stringFromDate:date];
    return [ExteriaCachedFormatter(@"clock", @"jmm", NSDateFormatterNoStyle) stringFromDate:date];
}
