import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/custom_image.dart';
import '../services/custom_image_service.dart';
import '../services/pictogram_service.dart';

class CustomImagesWidget extends StatefulWidget {
  final String idToken;
  final String aacUserId;

  const CustomImagesWidget({
    Key? key,
    required this.idToken,
    required this.aacUserId,
  }) : super(key: key);

  @override
  State<CustomImagesWidget> createState() => _CustomImagesWidgetState();
}

class _CustomImagesWidgetState extends State<CustomImagesWidget> {
  List<CustomImage> _images = [];
  bool _isLoading = false;
  String _status = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadImages() async {
    setState(() {
      _isLoading = true;
      _status = 'Loading custom images...';
    });

    try {
      final images = await CustomImageService.getCustomImages(
        idToken: widget.idToken,
        aacUserId: widget.aacUserId,
      );

      setState(() {
        _images = images.where((img) => !img.isProfileImage).toList();
        _status = _images.isEmpty 
            ? 'No custom images yet. Upload your first image!' 
            : '${_images.length} custom image(s)';
      });
    } catch (e) {
      setState(() {
        _status = 'Error loading images: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _reloadCache() async {
    setState(() {
      _isLoading = true;
      _status = 'Clearing cache and reloading images...';
    });

    try {
      // Clear the cache first
      CustomImageService.clearCache();
      
      // Force refresh from server
      final images = await CustomImageService.getCustomImages(
        idToken: widget.idToken,
        aacUserId: widget.aacUserId,
        forceRefresh: true,
      );

      setState(() {
        _images = images.where((img) => !img.isProfileImage).toList();
        _status = _images.isEmpty 
            ? 'No custom images found. Upload your first image!' 
            : 'Cache reloaded! ${_images.length} custom images loaded';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Images cache reloaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _images = [];
        _status = 'Error reloading cache: $e';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reload cache: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }


  Future<void> _uploadImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? imageFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (imageFile == null) return;

      final result = await showDialog<String>(
        context: context,
        builder: (context) => CustomImageUploadDialog(),
      );

      if (result == null) return;

      setState(() {
        _isLoading = true;
        _status = 'Uploading image...';
      });

      final uploadedImage = await CustomImageService.uploadImage(
        imageFile: File(imageFile.path),
        primaryTag: result,
        idToken: widget.idToken,
        aacUserId: widget.aacUserId,
      );

      if (uploadedImage != null) {
        CustomImageService.clearCache();
        await _loadImages(); // Refresh the list
        
        // Automatically clear pictogram cache so new image appears throughout the app
        try {
          await PictogramService.clearGlobalCache();
          debugPrint('🔄 Auto-cleared pictogram cache after image upload');
        } catch (e) {
          debugPrint('⚠️ Failed to auto-clear pictogram cache: $e');
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image uploaded and cache refreshed! New image will appear throughout the app.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _status = 'Upload failed: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _editImage(CustomImage image) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => CustomImageEditDialog(image: image),
    );

    if (result == null) return;

    try {
      setState(() {
        _isLoading = true;
        _status = 'Updating image...';
      });

      final updatedImage = await CustomImageService.updateImage(
        imageId: image.id,
        primaryTag: result,
        idToken: widget.idToken,
        aacUserId: widget.aacUserId,
      );

      if (updatedImage != null) {
        CustomImageService.clearCache();
        await _loadImages(); // Refresh the list
        
        // Automatically clear pictogram cache so updated image appears throughout the app
        try {
          await PictogramService.clearGlobalCache();
          debugPrint('🔄 Auto-cleared pictogram cache after image update');
        } catch (e) {
          debugPrint('⚠️ Failed to auto-clear pictogram cache: $e');
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image updated and cache refreshed!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _status = 'Update failed: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteImage(CustomImage image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Image'),
        content: Text('Are you sure you want to delete the image for \"${image.concept}/${image.subconcept}\"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      setState(() {
        _isLoading = true;
        _status = 'Deleting image...';
      });

      final success = await CustomImageService.deleteImage(
        imageId: image.id,
        idToken: widget.idToken,
        aacUserId: widget.aacUserId,
      );

      if (success) {
        CustomImageService.clearCache();
        await _loadImages(); // Refresh the list
        
        // Automatically clear pictogram cache so deleted image no longer appears throughout the app
        try {
          await PictogramService.clearGlobalCache();
          debugPrint('🔄 Auto-cleared pictogram cache after image deletion');
        } catch (e) {
          debugPrint('⚠️ Failed to auto-clear pictogram cache: $e');
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image deleted and cache refreshed!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _status = 'Delete failed: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<CustomImage> get _filteredImages {
    if (_searchController.text.isEmpty) return _images;
    return _images.where((image) => image.matchesQuery(_searchController.text)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.photo_library, color: Colors.blue),
            const SizedBox(width: 8),
            const Text(
              'Custom Images',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _reloadCache,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload Cache'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _uploadImage,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Upload'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 8),
        
        // Status
        Text(
          _status,
          style: TextStyle(
            color: _status.contains('Error') || _status.contains('failed') 
                ? Colors.red 
                : Colors.grey[600],
            fontSize: 12,
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Search bar
        if (_images.isNotEmpty) ...[
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search images by concept, subconcept, or tags...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) => setState(() {}),
          ),
          const SizedBox(height: 16),
        ],
        
        // Images grid
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_filteredImages.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(Icons.photo_library_outlined, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  _searchController.text.isEmpty
                      ? 'No custom images yet.\nUpload images to create personalized buttons!'
                      : 'No images match your search.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          )
        else
          CustomImagesGrid(
            images: _filteredImages,
            onEdit: _editImage,
            onDelete: _deleteImage,
          ),
      ],
    );
  }
}

class CustomImagesGrid extends StatelessWidget {
  final List<CustomImage> images;
  final Function(CustomImage) onEdit;
  final Function(CustomImage) onDelete;

  const CustomImagesGrid({
    Key? key,
    required this.images,
    required this.onEdit,
    required this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        final image = images[index];
        return CustomImageTile(
          image: image,
          onEdit: () => onEdit(image),
          onDelete: () => onDelete(image),
        );
      },
    );
  }
}

class CustomImageTile extends StatelessWidget {
  final CustomImage image;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const CustomImageTile({
    Key? key,
    required this.image,
    required this.onEdit,
    required this.onDelete,
  }) : super(key: key);

  bool _isLocalFileUrl(String url) {
    return url.startsWith('file://') || url.startsWith('/');
  }

  String _resolveLocalPath(String url) {
    if (url.startsWith('file://')) {
      return Uri.parse(url).toFilePath();
    }
    return url;
  }

  Widget _buildImageWidget(String url) {
    if (_isLocalFileUrl(url)) {
      final localPath = _resolveLocalPath(url);
      return Image.file(
        File(localPath),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[200],
            child: const Icon(Icons.broken_image, color: Colors.grey),
          );
        },
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Colors.grey[200],
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image
          Expanded(
            flex: 3,
            child: _buildImageWidget(image.imageUrl),
          ),
          
          // Info and actions
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Concept/Subconcept
                  Text(
                    image.concept,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (image.subconcept.isNotEmpty)
                    Text(
                      image.subconcept,
                      style: const TextStyle(fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  
                  const Spacer(),
                  
                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        tooltip: 'Edit',
                      ),
                      IconButton(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomImageUploadDialog extends StatefulWidget {
  const CustomImageUploadDialog({Key? key}) : super(key: key);

  @override
  State<CustomImageUploadDialog> createState() => _CustomImageUploadDialogState();
}

class _CustomImageUploadDialogState extends State<CustomImageUploadDialog> {
  final _primaryTagController = TextEditingController();

  @override
  void dispose() {
    _primaryTagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload Custom Image'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _primaryTagController,
              decoration: const InputDecoration(
                labelText: 'Primary Tag *',
                hintText: 'e.g., mom, dad, home, school',
                helperText: 'Use one tag per image, matching the web app flow.',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              maxLines: 1,
            ),
            const SizedBox(height: 8),
            const Text(
              '* Required fields',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_primaryTagController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please enter a primary tag'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            Navigator.of(context).pop(_primaryTagController.text.trim());
          },
          child: const Text('Upload'),
        ),
      ],
    );
  }
}

class CustomImageEditDialog extends StatefulWidget {
  final CustomImage image;

  const CustomImageEditDialog({
    Key? key,
    required this.image,
  }) : super(key: key);

  @override
  State<CustomImageEditDialog> createState() => _CustomImageEditDialogState();
}

class _CustomImageEditDialogState extends State<CustomImageEditDialog> {
  late final TextEditingController _primaryTagController;

  bool _isLocalFileUrl(String url) {
    return url.startsWith('file://') || url.startsWith('/');
  }

  String _resolveLocalPath(String url) {
    if (url.startsWith('file://')) {
      return Uri.parse(url).toFilePath();
    }
    return url;
  }

  @override
  void initState() {
    super.initState();
    _primaryTagController = TextEditingController(text: widget.image.subconcept);
  }

  @override
  void dispose() {
    _primaryTagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Custom Image'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Show image thumbnail
            Container(
              height: 120,
              width: 120,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _isLocalFileUrl(widget.image.imageUrl)
                    ? Image.file(
                        File(_resolveLocalPath(widget.image.imageUrl)),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.broken_image, color: Colors.grey);
                        },
                      )
                    : Image.network(
                        widget.image.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.broken_image, color: Colors.grey);
                        },
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _primaryTagController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Primary Tag *',
                hintText: 'e.g., mom, dad, home, school',
                helperText: 'This matches the web app custom image flow.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_primaryTagController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please enter a primary tag'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            Navigator.of(context).pop(_primaryTagController.text.trim());
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}