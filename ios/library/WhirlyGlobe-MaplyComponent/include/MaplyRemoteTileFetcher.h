/*
 *  MaplyRemoteTileFetcher.h
 *  WhirlyGlobe-MaplyComponent
 *
 *  Created by Steve Gifford on 6/15/18.
 *  Copyright 2011-2018 Saildrone Inc
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */

#import "MaplyTileSourceNew.h"
#import "MaplyCoordinateSystem.h"

/**
 Remote Tile Info Object (New)
 
 Not to be confused with the old one, which works with the older loading subsystem,
 the new remote tile info object contains min/max zoom, coordinate system and URL
 information for fetching individual data tiles.
 */
@interface MaplyRemoteTileInfoNew : NSObject<MaplyTileInfoNew>

/**
 Initialize with enough information to fetch remote tiles.
 
 This version of the init method takes all the explicit
 information needed to fetch remote tiles.  This includes the
 base URL and min and max zoom levels.
 
 @param baseURL The base URL for fetching TMS tiles.  This is a replacement URL with {x}, {y}, and {z} in the string.
 
 @param minZoom The minimum zoom level to fetch.  This really should be 0.
 
 @param maxZoom The maximum zoom level to fetch.
 
 @return The MaplyRemoteTileInfoNew object or nil on failure.
 */
- (nonnull instancetype)initWithBaseURL:(NSString *__nonnull)baseURL minZoom:(int)minZoom maxZoom:(int)maxZoom;

/// Base URL
@property (nonatomic,readonly,retain,nonnull) NSString *baseURL;

/// Min zoom level
@property (nonatomic,readonly,assign) int minZoom;

/// Max zoom level
@property (nonatomic,readonly,assign) int maxZoom;

/**
 The timeout assigned to the NSMutableURLRequest we're using to fetch tiles.
 
 This is not set by default.  If set, we'll use this value as the timeout on the NSMutableURLRequest we use for fetching tiles.  This lets you extent it where appropriate or shorten it if you like.
 */
@property (nonatomic,assign) float timeOut;

/**
 The cache directory for image tiles.
 
 In general, we want to cache.  The globe, in particular,
 is going to fetch the same tiles over and over, quite a lot.
 The cacheing behavior is a little dumb.  It will just write
 files to the given directory forever.  If you're interacting
 with a giant image pyramid, that could be problematic.
 */
@property (nonatomic, retain,nullable) NSString *cacheDir;

/**
 Optional headers to add to the NSURLRequest.
 
 These are name/data pairs which will be stuck in the NSURLRequest header.
 */
@property (nonatomic, retain) NSDictionary * __nullable headers;

@end

/**
    Fetch Info for remote tile fetches.
 
    The URL (required) and cacheFile (optional) for the given fetch.
    This is the object the RemoteTileFetcher expects for the fetchInfo member of the TileFetchRequest.
  */
@interface MaplyRemoteTileFetchInfo : NSObject

/// URL to fetch from
@property (nonatomic,nonnull,strong) NSURLRequest *urlReq;

/// File name for cached file (if present).  Save it here when fetched if set.
@property (nonatomic,nonnull,strong) NSString *cacheFile;

@end


@class MaplyRemoteTileFetcherStats;

/**
  Remote Tile fetcher fetches tiles from remote URLs.
 
  The tile fetcher interacts with loaders that want tiles, as demanded by samplers.
  It's complicated.  There's a default one of these that will get used if you pass in nil to the MaplyQuadImageLoader.
  */
@interface MaplyRemoteTileFetcher : NSObject<MaplyTileFetcher>

/// Initialize with the number of connections the fetcher can have open at once
- (instancetype __nonnull)initWithName:(NSString * __nonnull)name connections:(int)numConnections;

/// Number of outstanding connections in parallel
@property (nonatomic) int numConnections;

/// Return the fetching stats since the beginning or since the last reset
- (MaplyRemoteTileFetcherStats * __nullable)getStats:(bool)allTime;

/// Reset the counters for one variant of stat
- (void)resetStats;

// If set, you get way too much debugging output
@property (nonatomic,assign) bool debugMode;

@end

/// Stats collected by the fetcher
@interface MaplyRemoteTileFetcherStats : NSObject

@property (nonatomic,readonly,weak,nullable) MaplyRemoteTileFetcher *fetcher;

// Start of stats collection
@property (nonatomic,nonnull,strong) NSDate *startDate;

// Total requests, remote and cached
@property (nonatomic) int totalRequests;

// Requests that resulted in a remote HTTP call
@property (nonatomic) int remoteRequests;

// Total requests cancelled
@property (nonatomic) int totalCancels;

// Requests failed
@property (nonatomic) int totalFails;

// Bytes of remote data loaded
@property (nonatomic) int remoteData;

// Bytes of cached data loaded
@property (nonatomic) int localData;

// Total time spent waiting for successful remote data requests
@property (nonatomic) NSTimeInterval totalLatency;

// Add the given stats to ours
- (void)addStats:(MaplyRemoteTileFetcherStats * __nonnull)stats;

// Print out the stats
- (void)dump;

@end
