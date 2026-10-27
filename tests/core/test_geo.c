#include "exteria_geo.h"
#include "exteria_messages.h"
#include "exteria_bots.h"
#include "exteria_tl_ids.h"
#include "test_util.h"
#include <math.h>

static void projection(void) {
    const double points[][2] = {{0,0},{55.03,82.92},{-33.87,151.21},{85,179.99},{-85,-179.99},{90,180}};
    for (size_t i = 0; i < sizeof(points)/sizeof(points[0]); ++i) {
        double x,y,lat,lon;
        CHECK_EQ_INT(exteria_map_project(points[i][0],points[i][1],&x,&y),EXTERIA_OK);
        CHECK(x>=0 && x<1 && y>=0 && y<=1);
        CHECK_EQ_INT(exteria_map_unproject(x,y,&lat,&lon),EXTERIA_OK);
        CHECK(fabs(lat-fmax(-EXTERIA_MAP_MAX_LATITUDE,fmin(EXTERIA_MAP_MAX_LATITUDE,points[i][0])))<1e-8);
        CHECK(fabs(lon-(points[i][1]==180 ? -180 : points[i][1]))<1e-8);
    }
    double x=1,y=1;
    CHECK_EQ_INT(exteria_map_project(NAN,0,&x,&y),EXTERIA_E_ARG);
    CHECK(x==0 && y==0);
    CHECK_EQ_INT(exteria_map_project(0,181,&x,&y),EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_map_unproject(INFINITY,0,&x,&y),EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_map_unproject(-0.25,2,&x,&y),EXTERIA_OK);
    CHECK(fabs(y-90)<1e-8 && fabs(x+EXTERIA_MAP_MAX_LATITUDE)<1e-8);
}

static void visible_tiles(void) {
    exteria_map_tile tiles[EXTERIA_MAP_MAX_TILES];
    size_t count=99;
    CHECK_EQ_INT(exteria_map_tiles(0,179.99,3,320,480,tiles,EXTERIA_MAP_MAX_TILES,&count),EXTERIA_OK);
    CHECK(count>0 && count<=6);
    int wraps=0;
    for(size_t i=0;i<count;++i) {
        CHECK(tiles[i].x<8 && tiles[i].y<8 && tiles[i].zoom==3);
        CHECK(tiles[i].left<320 && tiles[i].left+tiles[i].side>0);
        CHECK(tiles[i].top<480 && tiles[i].top+tiles[i].side>0);
        if(tiles[i].x==0) wraps=1;
    }
    CHECK(wraps);
    CHECK_EQ_INT(exteria_map_tiles(90,0,2,768,1024,tiles,EXTERIA_MAP_MAX_TILES,&count),EXTERIA_OK);
    for(size_t i=0;i<count;++i) CHECK(tiles[i].y<4);
    CHECK_EQ_INT(exteria_map_tiles(0,0,19,4096,4096,tiles,EXTERIA_MAP_MAX_TILES,&count),EXTERIA_E_LIMIT);
    CHECK_EQ_INT(count,0);
    CHECK_EQ_INT(exteria_map_tiles(0,0,2,320,480,tiles,1,&count),EXTERIA_E_LIMIT);
    CHECK_EQ_INT(count,0);
    CHECK_EQ_INT(exteria_map_tiles(0,0,NAN,320,480,tiles,64,&count),EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_map_tiles(0,0,20,320,480,tiles,64,&count),EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_map_tiles(0,0,1,0,480,tiles,64,&count),EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_map_tiles(0,0,1.5,320,480,tiles,64,&count),EXTERIA_OK);
    CHECK(fabs(tiles[0].side-256*sqrt(2))<1e-8);
}

static void protocol(void) {
    exteria_arena arena;
    exteria_arena_init(&arena,1024*1024);
    exteria_tl_value *geo=exteria_tl_new_obj(&arena,"geoPoint");
    CHECK_EQ_INT(exteria_tl_set_f64(&arena,geo,"lat",55.03),EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_f64(&arena,geo,"long",82.92),EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i64(&arena,geo,"access_hash",1),EXTERIA_OK);
    exteria_tl_value *media=exteria_tl_new_obj(&arena,"messageMediaVenue");
    CHECK_EQ_INT(exteria_tl_set(media,"geo",geo),EXTERIA_OK);
    const char *keys[]={"title","address","provider","venue_id","venue_type"};
    const char *values[]={"park","street","foursquare","123","outdoors"};
    for(size_t i=0;i<5;++i) CHECK_EQ_INT(exteria_tl_set_str(&arena,media,keys[i],values[i]),EXTERIA_OK);
    exteria_media_info info;
    exteria_media_classify(media,&info);
    CHECK_EQ_INT(info.kind,EXTERIA_PREVIEW_LOCATION);
    CHECK(info.location.valid && info.location.venue);
    CHECK(!strcmp(info.location.title,"park"));
    CHECK(fabs(info.location.latitude-55.03)<1e-8);
    exteria_peer_ref peer={0};
    peer.kind=1;peer.id=123;peer.access_hash=456;
    exteria_tl_value *request=NULL;
    CHECK_EQ_INT(exteria_send_location_request(&arena,&peer,&info.location,789,&request),EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request,"media"),EXTERIA_TL_ID_inputMediaVenue));
    exteria_writer writer;
    exteria_writer_init(&writer,2048);
    CHECK_EQ_INT(exteria_tl_encode(request,&writer,NULL),EXTERIA_OK);
    CHECK(writer.len>0);
    exteria_writer_free(&writer);
    info.location.venue=0;
    CHECK_EQ_INT(exteria_send_location_request(&arena,&peer,&info.location,789,&request),EXTERIA_OK);
    CHECK(exteria_tl_is(exteria_tl_get(request,"media"),EXTERIA_TL_ID_inputMediaGeoPoint));
    info.location.latitude=NAN;
    CHECK_EQ_INT(exteria_send_location_request(&arena,&peer,&info.location,789,&request),EXTERIA_E_ARG);
    CHECK(request==NULL);
    CHECK_EQ_INT(exteria_tl_set_f64(&arena,geo,"lat",91),EXTERIA_OK);
    exteria_media_classify(media,&info);
    CHECK(!info.location.valid);
    CHECK_EQ_INT(exteria_geo_read(NULL,NULL,&info.location),EXTERIA_E_MALFORMED);
    CHECK(!info.location.valid);
    CHECK_EQ_INT(exteria_tl_set_f64(&arena,geo,"lat",55.03),EXTERIA_OK);
    char long_title[302];
    for (size_t i=0;i<300;i+=2) { long_title[i]=(char)0xd0; long_title[i+1]=(char)0x90; }
    long_title[300]=0;
    CHECK_EQ_INT(exteria_tl_set_str(&arena,media,"title",long_title),EXTERIA_OK);
    exteria_media_classify(media,&info);
    CHECK(info.location.valid && info.location.venue);
    CHECK_EQ_INT(strlen(info.location.title),126);
    exteria_tl_value *empty=exteria_tl_new_obj(&arena,"geoPointEmpty");
    CHECK_EQ_INT(exteria_geo_read(empty,NULL,&info.location),EXTERIA_E_MALFORMED);
    exteria_tl_value *inline_message=exteria_tl_new_obj(&arena,"botInlineMessageMediaVenue");
    CHECK_EQ_INT(exteria_tl_set(inline_message,"geo",geo),EXTERIA_OK);
    for(size_t i=0;i<5;++i) CHECK_EQ_INT(exteria_tl_set_str(&arena,inline_message,keys[i],values[i]),EXTERIA_OK);
    exteria_tl_value *item=exteria_tl_new_obj(&arena,"botInlineResult");
    CHECK_EQ_INT(exteria_tl_set_str(&arena,item,"id","venue-1"),EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_str(&arena,item,"type","venue"),EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(item,"send_message",inline_message),EXTERIA_OK);
    exteria_tl_value *items=exteria_tl_new_vec(&arena,1);
    CHECK_EQ_INT(exteria_tl_vec_set(items,0,item),EXTERIA_OK);
    exteria_tl_value *answer=exteria_tl_new_obj(&arena,"messages.botResults");
    CHECK_EQ_INT(exteria_tl_set_i64(&arena,answer,"query_id",12),EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set_i32(&arena,answer,"cache_time",30),EXTERIA_OK);
    CHECK_EQ_INT(exteria_tl_set(answer,"results",items),EXTERIA_OK);
    exteria_inline_page page;
    exteria_inline_result row;
    size_t count=0;
    CHECK_EQ_INT(exteria_inline_results_parse(answer,&page,&row,1,&count),EXTERIA_OK);
    CHECK_EQ_INT(count,1);
    CHECK(row.media.location.valid && row.media.location.venue);
    CHECK(!strcmp(row.media.location.venue_id,"123"));
    CHECK_EQ_INT(exteria_tl_set_f64(&arena,geo,"lat",NAN),EXTERIA_OK);
    CHECK_EQ_INT(exteria_inline_results_parse(answer,&page,&row,1,&count),EXTERIA_OK);
    CHECK_EQ_INT(count,0);
    exteria_arena_free(&arena);
}

static void png_bounds(void) {
    uint8_t png[33]={137,80,78,71,13,10,26,10,0,0,0,13,'I','H','D','R',0,0,1,0,0,0,1,0};
    CHECK(exteria_map_png_header(png,sizeof(png)));
    CHECK(!exteria_map_png_header(png,23));
    CHECK(!exteria_map_png_header(png,EXTERIA_MAP_TILE_BYTES_MAX+1));
    CHECK(!exteria_map_png_header(NULL,33));
    png[18]=2; CHECK(!exteria_map_png_header(png,sizeof(png))); png[18]=1;
    png[11]=12; CHECK(!exteria_map_png_header(png,sizeof(png))); png[11]=13;
    png[0]='<'; CHECK(!exteria_map_png_header(png,sizeof(png)));
}

int main(void) {
    projection();visible_tiles();protocol();png_bounds();
    return test_finish("test_geo");
}
