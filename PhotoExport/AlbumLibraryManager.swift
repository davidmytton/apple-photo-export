//
//  AlbumLibraryManager.swift
//  PhotoExport
//
//  Created by David Mytton on 2025-02-16.
//


import SwiftUI
import Photos

/// Converts a PHFetchResult<T> into a Swift Array<T>.
func fetchResultToArray<T>(fetchResult: PHFetchResult<T>) -> [T] {
    var results = [T]()
    results.reserveCapacity(fetchResult.count)
    fetchResult.enumerateObjects { (obj, _, _) in
        results.append(obj)
    }
    return results
}

class AlbumLibraryManager: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var albums: [PHAssetCollection] = []
    @Published var isLoading: Bool = false
    
    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
        fetchAlbums()
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    func fetchAlbums() {
        isLoading = true
        
        // Fetch system "smart" albums (e.g., Recents, Favorites).
        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .albumRegular,
            options: nil
        )
        
        // Fetch user-created albums.
        let userCollections = PHCollectionList.fetchTopLevelUserCollections(with: nil)
        
        // Convert the PHFetchResult objects to arrays.
        let smartAlbumArray = fetchResultToArray(fetchResult: smartAlbums)
        let userCollectionArray = fetchResultToArray(fetchResult: userCollections)
        
        var albumList: [PHAssetCollection] = []
        
        // Add all smart albums.
        albumList.append(contentsOf: smartAlbumArray)
        
        // Add user-created albums (PHCollectionList can contain various PHCollection types).
        for item in userCollectionArray {
            if let assetCollection = item as? PHAssetCollection {
                albumList.append(assetCollection)
            }
        }
        
        // Sort the resulting array by album title.
        albumList.sort { ($0.localizedTitle ?? "") < ($1.localizedTitle ?? "") }
        
        // Update published property on the main thread.
        DispatchQueue.main.async {
            self.albums = albumList
            self.isLoading = false
        }
    }
    
    // Photo library change observer callback.
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async {
            self.fetchAlbums()
        }
    }
}
