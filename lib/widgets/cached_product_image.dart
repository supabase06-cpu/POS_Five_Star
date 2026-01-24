import 'dart:io';
import 'package:flutter/material.dart';
import '../services/image_cache_service.dart';

class CachedProductImage extends StatefulWidget {
  final String productId;
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CachedProductImage({
    Key? key,
    required this.productId,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  }) : super(key: key);

  @override
  State<CachedProductImage> createState() => _CachedProductImageState();
}

class _CachedProductImageState extends State<CachedProductImage> {
  final ImageCacheService _cacheService = ImageCacheService();
  String? _cachedImagePath;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedProductImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload if product ID or URL changed
    if (oldWidget.productId != widget.productId || 
        oldWidget.imageUrl != widget.imageUrl) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final cachedPath = await _cacheService.getCachedImagePath(
        widget.productId, 
        widget.imageUrl
      );

      if (mounted) {
        setState(() {
          _cachedImagePath = cachedPath;
          _isLoading = false;
          _hasError = cachedPath == null;
        });
      }
    } catch (e) {
      debugPrint('❌ CachedProductImage error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildPlaceholder();
    }

    if (_hasError || _cachedImagePath == null) {
      debugPrint('❌ CachedProductImage: Showing error widget for ${widget.productId} - hasError: $_hasError, cachedPath: $_cachedImagePath');
      return _buildErrorWidget();
    }

    debugPrint('✅ CachedProductImage: Showing image for ${widget.productId} from $_cachedImagePath');
    return Image.file(
      File(_cachedImagePath!),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('❌ CachedProductImage: Image.file error for ${widget.productId}: $error');
        return _buildErrorWidget();
      },
    );
  }

  Widget _buildPlaceholder() {
    return widget.placeholder ?? 
      Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
  }

  Widget _buildErrorWidget() {
    return widget.errorWidget ?? 
      Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.image_not_supported,
          color: Colors.grey[400],
          size: 32,
        ),
      );
  }
}