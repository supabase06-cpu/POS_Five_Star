import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  Database? _database;
  String? _cacheDir;

  /// Initialize the image cache service
  Future<void> initialize() async {
    // Initialize database factory for desktop platforms
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    
    await _initDatabase();
    await _initCacheDirectory();
    debugPrint('📁 Image cache initialized: $_cacheDir');
  }

  /// Initialize SQLite database for image metadata
  Future<void> _initDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'image_cache.db');

      _database = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE image_cache (
              product_id TEXT PRIMARY KEY,
              image_url TEXT NOT NULL,
              local_path TEXT NOT NULL,
              url_hash TEXT NOT NULL,
              cached_at INTEGER NOT NULL,
              file_size INTEGER NOT NULL
            )
          ''');
          
          // Index for faster lookups
          await db.execute('CREATE INDEX idx_product_id ON image_cache(product_id)');
          await db.execute('CREATE INDEX idx_url_hash ON image_cache(url_hash)');
        },
      );
      
      debugPrint('📁 Image cache database initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize image cache database: $e');
      rethrow;
    }
  }

  /// Initialize cache directory
  Future<void> _initCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = join(appDir.path, 'product_images');
    
    final cacheDirectory = Directory(_cacheDir!);
    if (!await cacheDirectory.exists()) {
      await cacheDirectory.create(recursive: true);
    }
  }

  /// Get cached image path or download if needed (Delta sync)
  Future<String?> getCachedImagePath(String productId, String imageUrl) async {
    if (_database == null || _cacheDir == null) {
      await initialize();
    }

    try {
      // Generate hash of the image URL for change detection
      final urlHash = _generateUrlHash(imageUrl);
      
      // Check if image exists in cache with same URL hash
      final cached = await _database!.query(
        'image_cache',
        where: 'product_id = ?',
        whereArgs: [productId],
      );

      if (cached.isNotEmpty) {
        final cachedRecord = cached.first;
        final cachedUrlHash = cachedRecord['url_hash'] as String;
        final localPath = cachedRecord['local_path'] as String;
        
        // URL hasn't changed, check if file still exists
        if (cachedUrlHash == urlHash) {
          // URL hasn't changed, check if file still exists
          final file = File(localPath);
          if (await file.exists()) {
            // Verify file integrity
            final fileSize = await file.length();
            final expectedSize = cachedRecord['file_size'] as int;
            
            if (fileSize == expectedSize && fileSize > 0) {
              debugPrint('📷 Using cached image for product $productId');
              return localPath;
            } else {
              debugPrint('❌ Cached image corrupted for product $productId (size: $fileSize, expected: $expectedSize)');
              await _deleteCachedImage(productId);
            }
          } else {
            debugPrint('❌ Cached image file missing for product $productId');
            await _deleteCachedImage(productId);
          }
        } else {
          debugPrint('📷 Image URL changed for product $productId, will re-download');
          // URL changed, delete old cache entry
          await _deleteCachedImage(productId);
        }
      }

      // Download and cache new image
      return await _downloadAndCacheImage(productId, imageUrl, urlHash);
      
    } catch (e) {
      debugPrint('❌ Error getting cached image for $productId: $e');
      return null;
    }
  }

  /// Download and cache image
  Future<String?> _downloadAndCacheImage(String productId, String imageUrl, String urlHash) async {
    try {
      debugPrint('📥 Downloading image for product $productId');
      
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        debugPrint('❌ Failed to download image: ${response.statusCode}');
        return null;
      }

      // Validate image data
      if (response.bodyBytes.isEmpty) {
        debugPrint('❌ Downloaded image is empty for product $productId');
        return null;
      }

      // Generate local file path
      final fileName = '${productId}_${urlHash.substring(0, 8)}.jpg';
      final localPath = join(_cacheDir!, fileName);
      
      // Save image to local storage
      final file = File(localPath);
      await file.writeAsBytes(response.bodyBytes);
      
      // Verify file was written correctly
      if (!await file.exists()) {
        debugPrint('❌ Failed to save image file for product $productId');
        return null;
      }

      final fileSize = await file.length();
      if (fileSize != response.bodyBytes.length) {
        debugPrint('❌ File size mismatch for product $productId: expected ${response.bodyBytes.length}, got $fileSize');
        await file.delete();
        return null;
      }
      
      // Save metadata to database
      await _database!.insert(
        'image_cache',
        {
          'product_id': productId,
          'image_url': imageUrl,
          'local_path': localPath,
          'url_hash': urlHash,
          'cached_at': DateTime.now().millisecondsSinceEpoch,
          'file_size': response.bodyBytes.length,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      debugPrint('✅ Image cached for product $productId: ${response.bodyBytes.length} bytes at $localPath');
      return localPath;
      
    } catch (e) {
      debugPrint('❌ Error downloading image for $productId: $e');
      return null;
    }
  }

  /// Generate hash for URL change detection
  String _generateUrlHash(String url) {
    final bytes = utf8.encode(url);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Delete cached image
  Future<void> _deleteCachedImage(String productId) async {
    try {
      // Get cached record
      final cached = await _database!.query(
        'image_cache',
        where: 'product_id = ?',
        whereArgs: [productId],
      );

      if (cached.isNotEmpty) {
        final localPath = cached.first['local_path'] as String;
        
        // Delete file
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
        
        // Delete database record
        await _database!.delete(
          'image_cache',
          where: 'product_id = ?',
          whereArgs: [productId],
        );
        
        debugPrint('🗑️ Deleted cached image for product $productId');
      }
    } catch (e) {
      debugPrint('❌ Error deleting cached image for $productId: $e');
    }
  }

  /// Bulk cache images for multiple products (Delta sync)
  Future<void> cacheProductImages(List<Map<String, dynamic>> products) async {
    debugPrint('📦 Starting bulk image cache for ${products.length} products');
    
    int downloaded = 0;
    int cached = 0;
    int failed = 0;

    for (final product in products) {
      final productId = product['id']?.toString();
      final imageUrl = product['image_url']?.toString();
      
      if (productId == null || imageUrl == null || imageUrl.isEmpty) {
        continue;
      }

      final cachedPath = await getCachedImagePath(productId, imageUrl);
      if (cachedPath != null) {
        // Check if it was downloaded or was already cached
        final file = File(cachedPath);
        final stats = await file.stat();
        if (stats.modified.isAfter(DateTime.now().subtract(const Duration(minutes: 1)))) {
          downloaded++;
        } else {
          cached++;
        }
      } else {
        failed++;
      }
    }

    debugPrint('📊 Image cache summary: $downloaded downloaded, $cached from cache, $failed failed');
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    if (_database == null) return {};

    try {
      final count = Sqflite.firstIntValue(
        await _database!.rawQuery('SELECT COUNT(*) FROM image_cache')
      ) ?? 0;

      final totalSize = Sqflite.firstIntValue(
        await _database!.rawQuery('SELECT SUM(file_size) FROM image_cache')
      ) ?? 0;

      return {
        'cached_images': count,
        'total_size_bytes': totalSize,
        'total_size_mb': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'cache_directory': _cacheDir,
      };
    } catch (e) {
      debugPrint('❌ Error getting cache stats: $e');
      return {};
    }
  }

  /// Clear all cached images
  Future<void> clearCache() async {
    try {
      // Delete all files
      if (_cacheDir != null) {
        final cacheDirectory = Directory(_cacheDir!);
        if (await cacheDirectory.exists()) {
          await cacheDirectory.delete(recursive: true);
          await cacheDirectory.create(recursive: true);
        }
      }

      // Clear database
      await _database?.delete('image_cache');
      
      debugPrint('🧹 Image cache cleared');
    } catch (e) {
      debugPrint('❌ Error clearing cache: $e');
    }
  }

  /// Clean up old cached images (older than specified days)
  Future<void> cleanupOldCache({int olderThanDays = 30}) async {
    try {
      final cutoffTime = DateTime.now()
          .subtract(Duration(days: olderThanDays))
          .millisecondsSinceEpoch;

      final oldRecords = await _database!.query(
        'image_cache',
        where: 'cached_at < ?',
        whereArgs: [cutoffTime],
      );

      for (final record in oldRecords) {
        final productId = record['product_id'] as String;
        await _deleteCachedImage(productId);
      }

      debugPrint('🧹 Cleaned up ${oldRecords.length} old cached images');
    } catch (e) {
      debugPrint('❌ Error cleaning up old cache: $e');
    }
  }

  /// Check if image is cached and up-to-date
  Future<bool> isImageCached(String productId, String imageUrl) async {
    if (_database == null) return false;

    try {
      final urlHash = _generateUrlHash(imageUrl);
      
      final cached = await _database!.query(
        'image_cache',
        where: 'product_id = ? AND url_hash = ?',
        whereArgs: [productId, urlHash],
      );

      if (cached.isNotEmpty) {
        final localPath = cached.first['local_path'] as String;
        final file = File(localPath);
        return await file.exists();
      }

      return false;
    } catch (e) {
      return false;
    }
  }
}