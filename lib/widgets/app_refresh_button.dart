import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_health_manager.dart';

/// Emergency refresh button for app recovery
class AppRefreshButton extends StatefulWidget {
  final VoidCallback? onRefreshComplete;
  final bool showAlways;
  final Color? backgroundColor;
  final Color? iconColor;
  
  const AppRefreshButton({
    Key? key,
    this.onRefreshComplete,
    this.showAlways = false,
    this.backgroundColor,
    this.iconColor,
  }) : super(key: key);
  
  @override
  State<AppRefreshButton> createState() => _AppRefreshButtonState();
}

class _AppRefreshButtonState extends State<AppRefreshButton>
    with SingleTickerProviderStateMixin {
  bool _isRefreshing = false;
  bool _showButton = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
    
    _showButton = widget.showAlways;
    
    if (_showButton) {
      _animationController.forward();
    }
    
    // Start health monitoring to show button when needed
    AppHealthManager.instance.startHealthMonitoring(
      onNeedsRefresh: _showRefreshButton,
      onTimeout: _showRefreshButton,
    );
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  void _showRefreshButton() {
    if (!_showButton && mounted) {
      setState(() {
        _showButton = true;
      });
      _animationController.forward();
      
      // Add haptic feedback to alert user
      HapticFeedback.heavyImpact();
    }
  }
  
  void _hideRefreshButton() {
    if (_showButton && mounted) {
      _animationController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _showButton = false;
          });
        }
      });
    }
  }
  
  Future<void> _performRefresh() async {
    if (_isRefreshing) return;
    
    setState(() {
      _isRefreshing = true;
    });
    
    try {
      // Provide user feedback
      HapticFeedback.mediumImpact();
      
      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Refreshing app...'),
              ],
            ),
          ),
        );
      }
      
      // Perform the refresh
      final success = await AppHealthManager.instance.refreshApp(force: true);
      
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // Show result
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success 
                ? '✅ App refreshed successfully!' 
                : '⚠️ Refresh completed with warnings'
            ),
            backgroundColor: success ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      
      // Hide button if refresh was successful
      if (success && !widget.showAlways) {
        await Future.delayed(const Duration(seconds: 2));
        _hideRefreshButton();
      }
      
      // Notify parent
      widget.onRefreshComplete?.call();
      
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // Show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Refresh failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_showButton) {
      return const SizedBox.shrink();
    }
    
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            margin: const EdgeInsets.all(8),
            child: FloatingActionButton(
              onPressed: _isRefreshing ? null : _performRefresh,
              backgroundColor: widget.backgroundColor ?? Colors.orange.shade600,
              heroTag: "app_refresh_button",
              tooltip: "Refresh App",
              child: _isRefreshing
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.iconColor ?? Colors.white,
                    ),
                  )
                : Icon(
                    Icons.refresh,
                    color: widget.iconColor ?? Colors.white,
                    size: 28,
                  ),
            ),
          ),
        );
      },
    );
  }
}

/// Simple refresh icon for toolbars
class AppRefreshIcon extends StatelessWidget {
  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  
  const AppRefreshIcon({
    Key? key,
    this.onPressed,
    this.color,
    this.size = 24,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed ?? () async {
        await AppHealthManager.instance.refreshApp();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔄 App refreshed'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      icon: Icon(
        Icons.refresh,
        color: color,
        size: size,
      ),
      tooltip: 'Refresh App',
    );
  }
}
