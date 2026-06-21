import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/page_models.dart';
import '../services/admin_pages_api_service.dart';
import '../services/user_settings_provider.dart';

class AdminPagesButtonsPage extends StatefulWidget {
  final int initialRows;
  final int initialCols;
  final String? initialPageName;
  const AdminPagesButtonsPage({Key? key, this.initialRows = 10, this.initialCols = 10, this.initialPageName}) : super(key: key);

  @override
  State<AdminPagesButtonsPage> createState() => _AdminPagesButtonsPageState();
}

class _AdminPagesButtonsPageState extends State<AdminPagesButtonsPage> {
  List<PageModel> allPages = [];
  PageModel? currentPage;
  int gridRows = 10;
  int gridCols = 10;
  bool isLoading = false;
  String? error;
  String? statusMessage;
  String? originalName; // For update

  final pageNameController = TextEditingController();
  final pageDisplayNameController = TextEditingController();

  AdminPagesApiService? apiService;

  PageButtonModel _cloneButton(PageButtonModel b) {
    return PageButtonModel(
      row: b.row,
      col: b.col,
      text: b.text,
      speechPhrase: b.speechPhrase,
      llmQuery: b.llmQuery,
      targetPage: b.targetPage,
      queryType: b.queryType,
      hidden: b.hidden,
      pictogramUrl: b.pictogramUrl,
      useCustomPictogram: b.useCustomPictogram,
    );
  }

  PageModel _clonePage(PageModel page) {
    return PageModel(
      name: page.name,
      displayName: page.displayName,
      buttons: page.buttons.map(_cloneButton).toList(),
    );
  }

  String _pageDropdownLabel(PageModel page) {
    final name = page.name.trim();
    final display = page.displayName.trim();
    if (display.isEmpty) return name;
    if (name.isEmpty || display.toLowerCase() == name.toLowerCase()) return display;
    return '$display [$name]';
  }

  ({List<PageModel> pages, String? warning}) _normalizePages(List<PageModel> pages) {
    final byName = <String, PageModel>{};
    var duplicateNameCount = 0;
    var invalidNameCount = 0;

    for (final page in pages) {
      final name = page.name.trim();
      if (name.isEmpty) {
        invalidNameCount += 1;
        continue;
      }

      final key = name.toLowerCase();
      final existing = byName[key];
      if (existing == null) {
        byName[key] = _clonePage(page);
        continue;
      }

      duplicateNameCount += 1;
      final existingScore = existing.buttons.length + (existing.displayName.trim().isNotEmpty ? 1 : 0);
      final candidateScore = page.buttons.length + (page.displayName.trim().isNotEmpty ? 1 : 0);
      if (candidateScore > existingScore) {
        byName[key] = _clonePage(page);
      }
    }

    final normalized = byName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final displayCounts = <String, int>{};
    for (final page in normalized) {
      final display = page.displayName.trim().toLowerCase();
      if (display.isEmpty) continue;
      displayCounts[display] = (displayCounts[display] ?? 0) + 1;
    }
    final duplicateDisplayGroups = displayCounts.values.where((count) => count > 1).length;

    final warningParts = <String>[];
    if (duplicateNameCount > 0) {
      warningParts.add('collapsed $duplicateNameCount duplicate page name entr${duplicateNameCount == 1 ? 'y' : 'ies'}');
    }
    if (invalidNameCount > 0) {
      warningParts.add('ignored $invalidNameCount page entr${invalidNameCount == 1 ? 'y' : 'ies'} without a name');
    }
    if (duplicateDisplayGroups > 0) {
      warningParts.add('$duplicateDisplayGroups duplicate display name group${duplicateDisplayGroups == 1 ? '' : 's'} detected');
    }

    final warning = warningParts.isEmpty ? null : 'Page data warning: ${warningParts.join('; ')}.';
    return (pages: normalized, warning: warning);
  }

  @override
  void initState() {
    super.initState();
    
    // Configure soft input mode for admin page (but don't show keyboard yet)
    _configureSoftInputMode();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
      apiService = AdminPagesApiService(
        apiBaseUrl: userSettings.apiBaseUrl,
        userId: userSettings.userId ?? '',
      );
      if (allPages.isEmpty) {
        fetchPages();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Get initialPageName from route arguments if not already set
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['initialPageName'] is String) {
      final initialPageName = args['initialPageName'] as String;
      // If we already have pages, select the matching one
      if (allPages.isNotEmpty) {
        final match = allPages.firstWhere(
          (p) => p.name.toLowerCase() == initialPageName.toLowerCase(),
          orElse: () => allPages.first,
        );
        selectPage(match);
      }
      // Otherwise, fetchPages will handle selection after loading
    }
  }

  Future<void> fetchPages() async {
    setState(() { isLoading = true; error = null; });
    try {
      final pages = await apiService!.fetchPages();
      final normalized = _normalizePages(pages);
      setState(() {
        allPages = normalized.pages;
        if (normalized.warning != null) {
          statusMessage = normalized.warning;
        }
        // Try to select initialPageName if provided
        final initialPageName = widget.initialPageName ?? (ModalRoute.of(context)?.settings.arguments is Map ? (ModalRoute.of(context)?.settings.arguments as Map)['initialPageName'] : null);
        if (allPages.isEmpty) {
          currentPage = null;
          pageNameController.clear();
          pageDisplayNameController.clear();
        } else if (initialPageName != null) {
          final match = allPages.firstWhere(
            (p) => p.name.toLowerCase() == initialPageName.toLowerCase(),
            orElse: () => allPages.first,
          );
          selectPage(match);
        } else {
          selectPage(allPages.first);
        }
      });
    } catch (e) {
      setState(() { error = e.toString(); });
    } finally {
      setState(() { isLoading = false; });
    }
  }

  void selectPage(PageModel? page) {
    setState(() {
      originalName = page?.name;
      if (page != null) {
        final editablePage = _clonePage(page);
        currentPage = editablePage;
        pageNameController.text = editablePage.name;
        pageDisplayNameController.text = editablePage.displayName;
        // Dynamically set grid size based on data
        if (editablePage.buttons.isNotEmpty) {
          gridRows = editablePage.buttons.map((b) => b.row).reduce((a, b) => a > b ? a : b) + 1;
          gridCols = editablePage.buttons.map((b) => b.col).reduce((a, b) => a > b ? a : b) + 1;
        } else {
          gridRows = widget.initialRows;
          gridCols = widget.initialCols;
        }
        // Ensure every cell has a button
        final neededButtons = <PageButtonModel>[];
        for (int row = 0; row < gridRows; row++) {
          for (int col = 0; col < gridCols; col++) {
            final existing = editablePage.buttons.firstWhere(
              (b) => b.row == row && b.col == col,
              orElse: () => PageButtonModel(row: row, col: col, text: ''),
            );
            if (!neededButtons.any((b) => b.row == row && b.col == col)) {
              neededButtons.add(existing);
            }
          }
        }
        editablePage.buttons = neededButtons;
      } else {
        currentPage = null;
        pageNameController.clear();
        pageDisplayNameController.clear();
      }
    });
  }

  Future<void> savePage() async {
    if (currentPage == null) return;
    // Validation: page name and display name must not be empty
    if (pageNameController.text.trim().isEmpty || pageDisplayNameController.text.trim().isEmpty) {
      setState(() { statusMessage = 'Page Name and Display Name are required.'; });
      return;
    }
    // Validation: at least one button must have a non-empty label
    final hasLabel = currentPage!.buttons.any((b) => b.text.trim().isNotEmpty);
    if (!hasLabel) {
      setState(() { statusMessage = 'At least one button must have a label.'; });
      return;
    }
    setState(() { isLoading = true; statusMessage = null; });
    try {
      final page = PageModel(
        name: pageNameController.text.trim(),
        displayName: pageDisplayNameController.text.trim(),
        buttons: currentPage!.buttons,
      );
      // If originalName is null, this is a new page (create)
      // If originalName is not null and name is unchanged, always update
      // If originalName is not null and name is changed, update with old name
      if (originalName == null) {
        await apiService!.savePage(page); // create
      } else {
        await apiService!.updatePage(page, originalName!); // update
      }
      setState(() { statusMessage = 'Page saved successfully!'; });
      await fetchPages();
    } catch (e) {
      setState(() { statusMessage = 'Error saving page: $e'; });
    } finally {
      setState(() { isLoading = false; });
    }
  }

  Future<void> deletePage() async {
    if (currentPage == null) return;
    setState(() { isLoading = true; statusMessage = null; });
    try {
      await apiService!.deletePage(currentPage!.name);
      setState(() { statusMessage = 'Page deleted.'; });
      await fetchPages();
      selectPage(allPages.isNotEmpty ? allPages.first : null);
    } catch (e) {
      setState(() { statusMessage = 'Error deleting page: $e'; });
    } finally {
      setState(() { isLoading = false; });
    }
  }

  void revertPage() {
    if (currentPage != null) {
      selectPage(currentPage);
      setState(() { statusMessage = 'Reverted changes.'; });
    }
  }

  Widget buildGrid() {
    // Always show a 10x10 grid, matching the web admin
    const int gridRows = 10;
    const int gridCols = 10;
    if (currentPage == null) {
      return const Center(child: Text('No grid data for this page.'));
    }
    // Build a 2D grid of PageButtonModel, filling empty cells
    final List<List<PageButtonModel>> grid = List.generate(
      gridRows,
      (row) => List.generate(
        gridCols,
        (col) => currentPage!.buttons.firstWhere(
          (b) => b.row == row && b.col == col,
          orElse: () => PageButtonModel(row: row, col: col, text: ''),
        ),
      ),
    );
    return SizedBox(
      width: 180 * gridCols.toDouble(), // match web min width per cell
      height: 60 * gridRows.toDouble(), // enough height for all fields
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.blueAccent)),
        child: Table(
          border: TableBorder.all(color: Colors.grey.shade300),
          defaultColumnWidth: const FlexColumnWidth(),
          children: List.generate(gridRows, (row) {
            return TableRow(
              children: List.generate(gridCols, (col) {
                final btn = grid[row][col];
                return Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: buildButtonCell(btn),
                );
              }),
            );
          }),
        ),
      ),
    );
  }

  Widget buildButtonCell(PageButtonModel btn) {
    return SizedBox(
      width: 110, // Limit cell width for 10x10 grid
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            btn.text.isNotEmpty ? btn.text : '(empty)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 14),
                  tooltip: 'Move Up',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: btn.row > 0 ? () => _moveButton(btn, -1, 0) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 14),
                  tooltip: 'Move Down',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: btn.row < gridRows - 1 ? () => _moveButton(btn, 1, 0) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 14),
                  tooltip: 'Move Left',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: btn.col > 0 ? () => _moveButton(btn, 0, -1) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 14),
                  tooltip: 'Move Right',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: btn.col < gridCols - 1 ? () => _moveButton(btn, 0, 1) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 14),
                  tooltip: 'Edit Button',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _showEditDialog(btn),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(PageButtonModel btn) {
    final labelController = TextEditingController(text: btn.text);
    final speechController = TextEditingController(text: btn.speechPhrase ?? '');
    final llmController = TextEditingController(text: btn.llmQuery ?? '');
    final queryTypeController = TextEditingController(text: btn.queryType ?? '');
    final customTargetController = TextEditingController();

    final specialTargets = <String>[
      '!freestyle',
      '!games',
      '!threads',
      '!favorites',
      '!mood',
      '!email',
      '!jokes',
      '!guess-who',
      '!spelling',
      '!numbers',
      '!music',
      '!compose',
    ];

    final normalTargets = allPages
        .map((p) => p.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final dropdownTargets = <String>{
      '',
      ...specialTargets,
      ...normalTargets,
    }.toList();

    String displayTargetLabel(String value) {
      if (value.isEmpty) return '(none)';
      if (value.startsWith('!')) return 'Special: $value';
      return 'Page: $value';
    }

    final existingTarget = (btn.targetPage ?? '').trim();
    String selectedTarget = dropdownTargets.contains(existingTarget)
        ? existingTarget
        : '__custom__';
    if (selectedTarget == '__custom__') {
      customTargetController.text = existingTarget;
    }

    bool hidden = btn.hidden;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Button'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: labelController,
                      decoration: const InputDecoration(labelText: 'Label'),
                      onTap: _showKeyboardWhenNeeded,
                    ),
                    TextField(
                      controller: speechController,
                      decoration: const InputDecoration(labelText: 'Speech Phrase'),
                      onTap: _showKeyboardWhenNeeded,
                    ),
                    DropdownButtonFormField<String>(
                      value: selectedTarget,
                      decoration: const InputDecoration(
                        labelText: 'Target Page',
                        helperText: 'Choose a page or special destination.',
                      ),
                      items: [
                        ...dropdownTargets.map(
                          (target) => DropdownMenuItem<String>(
                            value: target,
                            child: Text(displayTargetLabel(target)),
                          ),
                        ),
                        const DropdownMenuItem<String>(
                          value: '__custom__',
                          child: Text('Custom...'),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          selectedTarget = value ?? '';
                          if (selectedTarget != '__custom__') {
                            customTargetController.clear();
                          }
                        });
                      },
                    ),
                    if (selectedTarget == '__custom__')
                      TextField(
                        controller: customTargetController,
                        decoration: const InputDecoration(
                          labelText: 'Custom Target',
                          helperText: 'Example: !music or a page name',
                        ),
                        onTap: _showKeyboardWhenNeeded,
                      ),
                    TextField(
                      controller: llmController,
                      decoration: const InputDecoration(labelText: 'LLM Query'),
                      onTap: _showKeyboardWhenNeeded,
                    ),
                    TextField(
                      controller: queryTypeController,
                      decoration: const InputDecoration(labelText: 'Query Type'),
                      onTap: _showKeyboardWhenNeeded,
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: hidden,
                          onChanged: (v) {
                            setDialogState(() {
                              hidden = v ?? false;
                            });
                          },
                        ),
                        const Text('Hidden'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Clear'),
                          onPressed: () {
                            labelController.clear();
                            speechController.clear();
                            llmController.clear();
                            queryTypeController.clear();
                            customTargetController.clear();
                            setDialogState(() {
                              selectedTarget = '';
                              hidden = false;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final resolvedTarget = selectedTarget == '__custom__'
                        ? customTargetController.text.trim()
                        : selectedTarget;

                    setState(() {
                      btn.text = labelController.text;
                      btn.speechPhrase = speechController.text;
                      btn.targetPage = resolvedTarget;
                      btn.llmQuery = llmController.text;
                      btn.queryType = queryTypeController.text;
                      btn.hidden = hidden;
                      _updateButtonInPage(btn);
                    });
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Ensure the edited button is in the currentPage.buttons list
  void _updateButtonInPage(PageButtonModel btn) {
    if (currentPage == null) return;
    final idx = currentPage!.buttons.indexWhere((b) => b.row == btn.row && b.col == btn.col);
    if (idx >= 0) {
      currentPage!.buttons[idx] = btn;
    } else {
      currentPage!.buttons.add(btn);
    }
  }

  // Move button in the grid
  void _moveButton(PageButtonModel btn, int dRow, int dCol) {
    if (currentPage == null) return;
    final targetRow = btn.row + dRow;
    final targetCol = btn.col + dCol;
    if (targetRow < 0 || targetRow >= gridRows || targetCol < 0 || targetCol >= gridCols) return;
    final idx = currentPage!.buttons.indexWhere((b) => b.row == btn.row && b.col == btn.col);
    final targetIdx = currentPage!.buttons.indexWhere((b) => b.row == targetRow && b.col == targetCol);
    setState(() {
      if (idx >= 0) {
        if (targetIdx >= 0) {
          // Swap
          final temp = currentPage!.buttons[targetIdx];
          currentPage!.buttons[targetIdx] = currentPage!.buttons[idx];
          currentPage!.buttons[idx] = temp;
          currentPage!.buttons[idx].row = btn.row;
          currentPage!.buttons[idx].col = btn.col;
          currentPage!.buttons[targetIdx].row = targetRow;
          currentPage!.buttons[targetIdx].col = targetCol;
        } else {
          // Move to empty cell
          currentPage!.buttons[idx].row = targetRow;
          currentPage!.buttons[idx].col = targetCol;
        }
      }
    });
  }

  @override
  void dispose() {
    // Re-disable keyboard when leaving admin page
    _disableKeyboardForMainApp();
    
    pageNameController.dispose();
    pageDisplayNameController.dispose();
    super.dispose();
  }

  // *** KEYBOARD MANAGEMENT FOR ADMIN PAGES ***
  Future<void> _configureSoftInputMode() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('audio_routing');
        // Configure window to allow keyboard input
        await platform.invokeMethod('configureSoftInputMode');
        debugPrint('✅ Soft input mode configured for admin page');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to configure soft input mode: $e');
    }
  }

  Future<void> _showKeyboardWhenNeeded() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('audio_routing');
        await platform.invokeMethod('showKeyboard');
        debugPrint('✅ Keyboard shown for text field');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to show keyboard: $e');
    }
  }

  Future<void> _disableKeyboardForMainApp() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('audio_routing');
        await platform.invokeMethod('disableSoftKeyboard');
        debugPrint('✅ Keyboard disabled for main app');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to disable keyboard: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin: Pages & Buttons')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<PageModel>(
                          value: currentPage,
                          hint: const Text('Select Page'),
                          items: allPages
                              .map((p) => DropdownMenuItem<PageModel>(
                                    value: p,
                                    child: Text(_pageDropdownLabel(p)),
                                  ))
                              .toList(),
                          onChanged: selectPage,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          // Create new page logic
                          final newPage = PageModel(
                            name: '',
                            displayName: '',
                            buttons: [],
                          );
                          setState(() {
                            currentPage = newPage;
                            pageNameController.clear();
                            pageDisplayNameController.clear();
                          });
                        },
                        child: const Text('New Page'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: pageNameController,
                          decoration: const InputDecoration(labelText: 'Page Name'),
                          onTap: _showKeyboardWhenNeeded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: pageDisplayNameController,
                          decoration: const InputDecoration(labelText: 'Display Name'),
                          onTap: _showKeyboardWhenNeeded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: buildGrid(),
                      ),
                    ),
                  ),
                  // Replace the Row for action buttons and status message
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: savePage,
                        child: const Text('Save'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: deletePage,
                        child: const Text('Delete'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: revertPage,
                        child: const Text('Revert'),
                      ),
                    ],
                  ),
                  if (statusMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      statusMessage!,
                      style: TextStyle(color: statusMessage!.contains('success') ? Colors.green : Colors.red),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
