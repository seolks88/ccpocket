import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/image_paste_shortcut.dart';
import '../models/messages.dart';
import '../services/native_paste_bridge.dart';
import '../utils/platform_helper.dart';
import '../utils/diff_parser.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/code_text_style.dart';
import 'bubbles/image_preview.dart';

/// Horizontal inset shared by the composer container and the completion /
/// mention overlays. Kept in one place so the overlay width can be derived
/// from the same value and can't drift from the field padding.
///
/// The overlay (in `chat_input_with_overlays.dart`) anchors at this inset and
/// sizes its follower to `screenWidth - 2 * _kComposerHPadding`.
const double _kComposerHPadding = AppSpacing.sm;

/// Painted size of a composer control. The *hit area* is grown to
/// [AppSizes.minTouchTarget] via [_ComposerIconButton]; the glyph/pill stays
/// this compact to preserve density.
const double _kComposerButtonSize = 36;

/// Painted size of the prominent action controls (send / stop / voice) — a
/// touch larger than the toolbar glyphs so the primary action reads first.
const double _kComposerActionButtonSize = 40;

/// Bottom input bar with slash-command button, text field, and action buttons.
///
/// Pure presentation — all actions are dispatched via callbacks.
///
/// Desktop keyboard shortcuts (handled in [_InputTextField]):
/// - Tab: indent current line(s)
/// - Shift+Tab: dedent current line(s)
/// - Active completion overlays handle navigation/selection first.
class ChatInputBar extends StatelessWidget {
  final TextEditingController inputController;
  final ProcessStatus status;
  final bool hasInputText;
  final bool isInputEmpty;
  final bool isVoiceAvailable;
  final bool isRecording;
  final bool isTranscribing;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onInterrupt;
  final VoidCallback onToggleVoice;
  final VoidCallback onIndent;
  final VoidCallback onDedent;
  final bool canDedent;
  final VoidCallback onSlashCommand;
  final VoidCallback onMention;
  final VoidCallback? onDollarMention;
  final bool isInMentionContext;
  final bool showDollarButton;
  final VoidCallback? onShowPromptHistory;
  final VoidCallback? onAttachImage;
  final List<({Uint8List bytes, String mimeType})> attachedImages;
  final void Function([int? index])? onClearImage;
  final DiffSelection? attachedDiffSelection;
  final VoidCallback? onClearDiffSelection;
  final VoidCallback? onTapDiffPreview;
  final String? hintText;

  /// Callback to paste an image from clipboard (desktop only).
  /// When set, [imagePasteShortcut] attempts image paste.
  /// Returns true if an image was found and pasted.
  final Future<bool> Function()? onPasteImage;

  /// Shortcut used to attach an image from the clipboard on desktop.
  final ImagePasteShortcut imagePasteShortcut;

  /// Handles keyboard events while an input completion overlay is open.
  final KeyEventResult Function(KeyEvent event)? onCompletionKeyEvent;

  const ChatInputBar({
    super.key,
    required this.inputController,
    required this.status,
    required this.hasInputText,
    this.isInputEmpty = true,
    required this.isVoiceAvailable,
    required this.isRecording,
    this.isTranscribing = false,
    required this.onSend,
    required this.onStop,
    required this.onInterrupt,
    required this.onToggleVoice,
    required this.onIndent,
    required this.onDedent,
    this.canDedent = true,
    required this.onSlashCommand,
    required this.onMention,
    this.onDollarMention,
    this.isInMentionContext = false,
    this.showDollarButton = false,
    this.onShowPromptHistory,
    this.onAttachImage,
    this.attachedImages = const [],
    this.onClearImage,
    this.attachedDiffSelection,
    this.onClearDiffSelection,
    this.onTapDiffPreview,
    this.hintText,
    this.onPasteImage,
    this.imagePasteShortcut = ImagePasteShortcut.ctrlV,
    this.onCompletionKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.only(
        left: _kComposerHPadding,
        right: _kComposerHPadding,
        top: AppSpacing.sm,
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        boxShadow: AppElevation.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachedDiffSelection != null)
            _DiffPreview(
              selection: attachedDiffSelection!,
              onTap: onTapDiffPreview,
              onClear: onClearDiffSelection,
            ),
          if (attachedImages.isNotEmpty)
            _ImagePreview(images: attachedImages, onClearImage: onClearImage),
          _InputTextField(
            controller: inputController,
            status: status,
            hintText: hintText,
            onSend: onSend,
            hasInputText: hasInputText,
            onPasteImage: onPasteImage,
            imagePasteShortcut: imagePasteShortcut,
            onCompletionKeyEvent: onCompletionKeyEvent,
            onIndent: onIndent,
            onDedent: onDedent,
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              AnimatedSwitcher(
                duration: motionDuration(context, AppMotion.standard),
                child: isInputEmpty
                    ? _SlashCommandButton(
                        key: const ValueKey('slash_command_button'),
                        onTap: onSlashCommand,
                      )
                    : _DedentButton(
                        key: const ValueKey('dedent_button'),
                        onTap: onDedent,
                        enabled: canDedent,
                      ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _IndentButton(onTap: onIndent),
              const SizedBox(width: AppSpacing.sm),
              _MentionButton(onTap: onMention, enabled: !isInMentionContext),
              if (showDollarButton) ...[
                const SizedBox(width: AppSpacing.sm),
                _DollarButton(onTap: onDollarMention ?? () {}),
              ],
              const SizedBox(width: AppSpacing.sm),
              _AttachButton(
                hasAttachment: attachedImages.isNotEmpty,
                imageCount: attachedImages.length,
                onTap: onAttachImage,
              ),
              if (onShowPromptHistory != null) ...[
                const SizedBox(width: AppSpacing.sm),
                _HistoryButton(onTap: onShowPromptHistory!),
              ],
              const Spacer(),
              if (isVoiceAvailable) ...[
                _VoiceButton(
                  isRecording: isRecording,
                  isTranscribing: isTranscribing,
                  onTap: onToggleVoice,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              _ActionButton(
                status: status,
                hasInputText: hasInputText,
                onSend: onSend,
                onStop: onStop,
                onInterrupt: onInterrupt,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Unified composer control: one radius/color recipe with a hit area grown to
/// [AppSizes.minTouchTarget]. The painted pill stays [_kComposerButtonSize] so
/// density is preserved while every control clears the 44px touch standard.
///
/// Used by the toolbar icon buttons and the send / stop / voice buttons so the
/// composer's tap targets all resolve to a single recipe.
class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    this.buttonKey,
    required this.tooltip,
    required this.color,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.enabled = true,
    this.paintOwnSurface = false,
    this.size = _kComposerButtonSize,
  });

  final Key? buttonKey;
  final String tooltip;

  /// Fill behind the glyph, painted on the compact pill (not the hit area).
  /// Pass [Colors.transparent] together with [paintOwnSurface] when [child]
  /// paints its own surface (e.g. the voice button's animated container).
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Painted glyph/content, centered inside the compact pill.
  final Widget child;

  /// When false the control is dimmed and its callbacks are disabled.
  final bool enabled;

  /// When true the child supplies its own sized/decorated surface; this widget
  /// only contributes the shared radius + grown hit area.
  final bool paintOwnSurface;

  /// Painted pill size (the hit area is always >= [AppSizes.minTouchTarget]).
  /// Defaults to the toolbar size; send/stop pass [_kComposerActionButtonSize]
  /// so the primary actions stay prominent and match the voice surface.
  final double size;

  @override
  Widget build(BuildContext context) {
    // Compact painted pill — stays [size] (~36) so density is preserved.
    final pill = paintOwnSurface
        ? child
        : Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            child: child,
          );

    // Transparent hit area grown to the 44px standard; the InkWell splash
    // covers the full target while the colored pill above stays compact.
    Widget control = Material(
      color: Colors.transparent,
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSizes.minTouchTarget,
            minHeight: AppSizes.minTouchTarget,
          ),
          child: Center(child: pill),
        ),
      ),
    );

    if (!enabled) {
      control = Opacity(opacity: 0.4, child: control);
    }

    return Tooltip(message: tooltip, child: control);
  }
}

class _IndentButton extends StatelessWidget {
  const _IndentButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return _ComposerIconButton(
      buttonKey: const ValueKey('indent_button'),
      tooltip: l.tooltipIndent,
      color: cs.surfaceContainerHigh,
      onTap: onTap,
      child: Icon(
        Icons.format_indent_increase,
        size: AppIconSize.action,
        color: cs.primary,
      ),
    );
  }
}

class _DedentButton extends StatelessWidget {
  const _DedentButton({super.key, required this.onTap, required this.enabled});
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return _ComposerIconButton(
      tooltip: l.tooltipDedent,
      color: cs.surfaceContainerHigh,
      enabled: enabled,
      onTap: onTap,
      child: Icon(
        Icons.format_indent_decrease,
        size: AppIconSize.action,
        color: cs.primary,
      ),
    );
  }
}

class _SlashCommandButton extends StatelessWidget {
  const _SlashCommandButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return _ComposerIconButton(
      tooltip: l.tooltipSlashCommand,
      color: cs.surfaceContainerHigh,
      onTap: onTap,
      child: Text(
        '/',
        style: TextStyle(
          fontSize: AppIconSize.action,
          fontWeight: FontWeight.bold,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _MentionButton extends StatelessWidget {
  const _MentionButton({required this.onTap, required this.enabled});
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return _ComposerIconButton(
      buttonKey: const ValueKey('mention_button'),
      tooltip: l.tooltipMention,
      color: cs.surfaceContainerHigh,
      enabled: enabled,
      onTap: onTap,
      child: Text(
        '@',
        style: TextStyle(
          fontSize: AppIconSize.action,
          fontWeight: FontWeight.bold,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _DollarButton extends StatelessWidget {
  const _DollarButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return _ComposerIconButton(
      buttonKey: const ValueKey('dollar_button'),
      tooltip: l.tooltipDollarMention,
      color: cs.surfaceContainerHigh,
      onTap: onTap,
      child: Text(
        r'$',
        style: TextStyle(
          fontSize: AppIconSize.action,
          fontWeight: FontWeight.bold,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  const _AttachButton({
    required this.hasAttachment,
    required this.imageCount,
    required this.onTap,
  });
  final bool hasAttachment;
  final int imageCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return _ComposerIconButton(
      buttonKey: const ValueKey('attach_image_button'),
      tooltip: l.tooltipAttachImage,
      color: hasAttachment ? cs.primaryContainer : cs.surfaceContainerHigh,
      onTap: onTap,
      child: hasAttachment
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.image,
                  size: AppIconSize.action,
                  color: cs.onPrimaryContainer,
                ),
                if (imageCount > 1)
                  Positioned(
                    top: -6,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        '$imageCount',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: cs.onPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : Icon(
              Icons.image_outlined,
              size: AppIconSize.action,
              color: cs.primary,
            ),
    );
  }
}

class _HistoryButton extends StatelessWidget {
  const _HistoryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return _ComposerIconButton(
      buttonKey: const ValueKey('prompt_history_button'),
      tooltip: l.tooltipPromptHistory,
      color: cs.surfaceContainerHigh,
      onTap: onTap,
      child: Icon(Icons.history, size: AppIconSize.action, color: cs.primary),
    );
  }
}

/// Theme-aware dismiss control for the image / diff preview chips.
///
/// Replaces the old `Colors.black54` circle + white glyph with a neutral
/// theme chip behind a [cs.onSurface] glyph. The painted dot stays compact; a
/// transparent hit area grows the target to [AppSizes.minTouchTarget].
class _PreviewDismissButton extends StatelessWidget {
  const _PreviewDismissButton({
    required this.tooltip,
    required this.onTap,
    this.alignment = Alignment.center,
  });

  final String tooltip;
  final VoidCallback? onTap;

  /// Where the compact dot sits inside the 44px hit box. Anchored to
  /// [Alignment.topRight] on image chips so the dot stays in the corner while
  /// the hit area extends inward over the thumbnail.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSizes.minTouchTarget,
            minHeight: AppSizes.minTouchTarget,
          ),
          child: Align(
            alignment: alignment,
            child: Container(
              decoration: BoxDecoration(
                color: appColors.neutralChip,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Icon(
                Icons.close,
                size: AppIconSize.inline,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.images, required this.onClearImage});
  final List<({Uint8List bytes, String mimeType})> images;
  final void Function([int? index])? onClearImage;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SizedBox(
        height: 80,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: images.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          FullScreenImageViewer(bytes: images[index].bytes),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Image.memory(
                      images[index].bytes,
                      height: 80,
                      width: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  top: AppSpacing.xs,
                  right: AppSpacing.xs,
                  child: _PreviewDismissButton(
                    tooltip: l.tooltipRemoveImage,
                    alignment: Alignment.topRight,
                    onTap: () => onClearImage?.call(index),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DiffPreview extends StatelessWidget {
  const _DiffPreview({
    required this.selection,
    required this.onTap,
    required this.onClear,
  });
  final DiffSelection selection;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final previewSummary = summarizeDiffSelection(selection.diffText);
    final summaryParts = <String>[];
    if (previewSummary.changedLineCount > 0) {
      summaryParts.add(l.changedLines(previewSummary.changedLineCount));
    }
    if (previewSummary.hunkCount > 0) {
      summaryParts.add(l.hunkCount(previewSummary.hunkCount));
    } else if (previewSummary.fileCount > 0) {
      summaryParts.add(l.fileCount(previewSummary.fileCount));
    }

    final summary = summaryParts.isNotEmpty
        ? summaryParts.join(' · ')
        : l.fileCount(
            previewSummary.fileCount > 0 ? previewSummary.fileCount : 1,
          );

    final previewLines = <String>[];
    final filePath = previewSummary.primaryFilePath;
    if (filePath != null && filePath.isNotEmpty) {
      previewLines.add(filePath);
    }
    final hunkHeader = previewSummary.primaryHunkHeader;
    if (hunkHeader != null && hunkHeader.isNotEmpty) {
      previewLines.add(hunkHeader);
    }
    if (previewLines.isEmpty) {
      previewLines.add(summary);
    }
    final preview = previewLines.join('\n');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.difference, size: AppIconSize.action, color: cs.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    style: codeTextSettingsOf(context).style(
                      fontSize: 10,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _PreviewDismissButton(tooltip: l.tooltipClearDiff, onTap: onClear),
          ],
        ),
      ),
    );
  }
}

class _InputTextField extends StatefulWidget {
  const _InputTextField({
    required this.controller,
    required this.status,
    this.hintText,
    required this.onSend,
    required this.hasInputText,
    this.onPasteImage,
    required this.imagePasteShortcut,
    this.onCompletionKeyEvent,
    this.onIndent,
    this.onDedent,
  });
  final TextEditingController controller;
  final ProcessStatus status;
  final String? hintText;
  final VoidCallback onSend;
  final bool hasInputText;

  /// Callback to paste an image from clipboard.
  /// Returns true if an image was pasted.
  final Future<bool> Function()? onPasteImage;

  /// Shortcut used to attach an image from the clipboard on desktop.
  final ImagePasteShortcut imagePasteShortcut;

  /// Gives active completion overlays first chance to handle navigation,
  /// dismissal, and selection shortcuts.
  final KeyEventResult Function(KeyEvent event)? onCompletionKeyEvent;

  /// Callback for Tab key (indent).
  final VoidCallback? onIndent;

  /// Callback for Shift+Tab key (dedent).
  final VoidCallback? onDedent;

  @override
  State<_InputTextField> createState() => _InputTextFieldState();
}

class _InputTextFieldState extends State<_InputTextField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    _focusNode.addListener(_syncNativePasteBridge);
  }

  @override
  void didUpdateWidget(covariant _InputTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePasteShortcut != widget.imagePasteShortcut) {
      _syncNativePasteBridge();
    }
  }

  @override
  void dispose() {
    NativePasteBridge.instance.deactivate(this);
    _focusNode.removeListener(_syncNativePasteBridge);
    _focusNode.dispose();
    super.dispose();
  }

  void _syncNativePasteBridge() {
    if (_focusNode.hasFocus &&
        widget.imagePasteShortcut != ImagePasteShortcut.commandV) {
      NativePasteBridge.instance.activate(this, _handleNativeTextPaste);
    } else {
      NativePasteBridge.instance.deactivate(this);
    }
  }

  bool _handleNativeTextPaste(String text) {
    if (!_focusNode.hasFocus || text.isEmpty) return false;
    _insertTextAtSelection(text);
    return true;
  }

  /// On desktop: Enter sends, Shift+Enter inserts newline,
  /// Tab indents, Shift+Tab dedents.
  /// Ctrl+K deletes to end of line, Ctrl+D deletes the next character.
  /// Image paste shortcuts attach clipboard images without blocking normal
  /// Cmd+V text paste unless the legacy Cmd+V mode is selected.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final isImeComposing =
        widget.controller.value.composing.isValid &&
        !widget.controller.value.composing.isCollapsed;
    if (!isImeComposing && widget.onCompletionKeyEvent != null) {
      final completionResult = widget.onCompletionKeyEvent!(event);
      if (completionResult == KeyEventResult.handled) {
        return completionResult;
      }
    }
    if (!isDesktopPlatform) return KeyEventResult.ignored;

    if (_isControlStyleTextShortcut(
      event,
      key: LogicalKeyboardKey.keyK,
      controlCharacter: 0x0b,
    )) {
      _deleteToEndOfLine();
      return KeyEventResult.handled;
    }

    if (_isControlStyleTextShortcut(
      event,
      key: LogicalKeyboardKey.keyD,
      controlCharacter: 0x04,
    )) {
      _deleteForwardCharacter();
      return KeyEventResult.handled;
    }

    final isModifier =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (widget.onPasteImage != null && _isImagePasteShortcut(event)) {
      if (widget.imagePasteShortcut == ImagePasteShortcut.commandV) {
        _handleImagePasteWithTextFallback();
      } else {
        _handleImagePasteOnly();
      }
      return KeyEventResult.handled;
    }

    // Tab / Shift+Tab: indent / dedent (IDE-like)
    if (event.logicalKey == LogicalKeyboardKey.tab && !isModifier) {
      if (isImeComposing) {
        return KeyEventResult.ignored;
      }
      if (HardwareKeyboard.instance.isShiftPressed) {
        widget.onDedent?.call();
      } else {
        widget.onIndent?.call();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    // IME変換中はEnterを無視（変換確定に使われるため）
    if (isImeComposing) {
      return KeyEventResult.ignored;
    }
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    if (isShiftPressed) {
      // Shift+Enter: let TextField handle newline insertion
      return KeyEventResult.ignored;
    }
    // Enter without Shift: send message
    if (widget.hasInputText) {
      widget.onSend();
    }
    return KeyEventResult.handled;
  }

  bool _isControlStyleTextShortcut(
    KeyEvent event, {
    required LogicalKeyboardKey key,
    required int controlCharacter,
    bool allowNullCharacter = true,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (event.logicalKey != key) return false;

    final hardware = HardwareKeyboard.instance;
    if (hardware.isMetaPressed ||
        hardware.isAltPressed ||
        hardware.isShiftPressed) {
      return false;
    }
    if (hardware.isControlPressed) return true;

    // macOS can deliver Ctrl+letter text-editing bindings without the control
    // modifier set. Treat non-printing variants as shortcut input, while
    // allowing normal printable letters to be typed.
    final character = event.character;
    if (character == null) return allowNullCharacter;
    final runes = character.runes.toList(growable: false);
    return runes.length == 1 && runes.single == controlCharacter;
  }

  void _deleteToEndOfLine() {
    final value = widget.controller.value;
    final selection = value.selection;
    if (!selection.isValid) return;

    final text = value.text;
    if (!selection.isCollapsed) {
      widget.controller.value = _replaceRange(
        value,
        selection.start,
        selection.end,
        '',
      );
      return;
    }

    final cursor = selection.baseOffset;
    final lineEnd = text.indexOf('\n', cursor);
    final end = lineEnd < 0 ? text.length : lineEnd;
    if (end == cursor) return;
    widget.controller.value = _replaceRange(value, cursor, end, '');
  }

  void _deleteForwardCharacter() {
    final value = widget.controller.value;
    final selection = value.selection;
    if (!selection.isValid) return;

    if (!selection.isCollapsed) {
      widget.controller.value = _replaceRange(
        value,
        selection.start,
        selection.end,
        '',
      );
      return;
    }

    final cursor = selection.baseOffset;
    if (cursor >= value.text.length) return;
    widget.controller.value = _replaceRange(value, cursor, cursor + 1, '');
  }

  TextEditingValue _replaceRange(
    TextEditingValue value,
    int start,
    int end,
    String replacement,
  ) {
    final text = value.text;
    final normalizedStart = start.clamp(0, text.length);
    final normalizedEnd = end.clamp(normalizedStart, text.length);
    final newText =
        text.substring(0, normalizedStart) +
        replacement +
        text.substring(normalizedEnd);
    final newCursor = normalizedStart + replacement.length;
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  bool _isImagePasteShortcut(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.keyV ||
        HardwareKeyboard.instance.isShiftPressed) {
      return false;
    }
    final hardware = HardwareKeyboard.instance;
    return switch (widget.imagePasteShortcut) {
      ImagePasteShortcut.ctrlV =>
        !hardware.isMetaPressed &&
            _isControlStyleTextShortcut(
              event,
              key: LogicalKeyboardKey.keyV,
              controlCharacter: 0x16,
              allowNullCharacter: false,
            ),
      ImagePasteShortcut.commandV =>
        hardware.isMetaPressed && !hardware.isControlPressed,
    };
  }

  Future<void> _handleImagePasteOnly() async {
    await widget.onPasteImage!();
  }

  Future<void> _handleImagePasteWithTextFallback() async {
    // Try image paste first
    final pasted = await widget.onPasteImage!();
    if (pasted) return;

    // Fall back to text paste from system clipboard
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _insertTextAtSelection(data.text!);
    }
  }

  void _insertTextAtSelection(String insertedText) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final normalizedStart = start.clamp(0, text.length);
    final normalizedEnd = end.clamp(normalizedStart, text.length);
    final newText =
        text.substring(0, normalizedStart) +
        insertedText +
        text.substring(normalizedEnd);
    final newCursor = normalizedStart + insertedText.length;
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return TextField(
      key: const ValueKey('message_input'),
      focusNode: _focusNode,
      controller: widget.controller,
      decoration: InputDecoration(
        hintText: widget.hintText ?? l.messagePlaceholder,
        filled: true,
        fillColor: cs.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(
            color: cs.primary.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        isDense: true,
        // 24px pill radius is intentional for the multiline field (no AppRadius
        // step matches); vertical 10 keeps the compact height. Only the
        // horizontal inset is routed through the spacing scale.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 10,
        ),
      ),
      enabled: widget.status != ProcessStatus.starting,
      autofillHints: null,
      maxLines: 6,
      minLines: 1,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.status,
    required this.hasInputText,
    required this.onSend,
    required this.onStop,
    required this.onInterrupt,
  });
  final ProcessStatus status;
  final bool hasInputText;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onInterrupt;

  @override
  Widget build(BuildContext context) {
    if (status == ProcessStatus.starting) {
      return _SendButton(onSend: onSend, enabled: false);
    }
    if (status != ProcessStatus.idle && !hasInputText) {
      return _StopButton(onInterrupt: onInterrupt, onStop: onStop);
    }
    return _SendButton(onSend: onSend, enabled: hasInputText);
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({required this.onInterrupt, required this.onStop});
  final VoidCallback onInterrupt;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return _ComposerIconButton(
      buttonKey: const ValueKey('stop_button'),
      tooltip: l.tapInterruptHoldStop,
      size: _kComposerActionButtonSize,
      color: cs.error,
      onTap: onInterrupt,
      onLongPress: onStop,
      child: Icon(
        Icons.stop_rounded,
        color: cs.onError,
        size: AppIconSize.action,
      ),
    );
  }
}

class _VoiceButton extends StatelessWidget {
  const _VoiceButton({
    required this.isRecording,
    required this.isTranscribing,
    required this.onTap,
  });
  final bool isRecording;
  final bool isTranscribing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    // The voice control keeps its bespoke animated surface (border + recording
    // glow + transcribing spinner). _ComposerIconButton only contributes the
    // shared radius + 44px hit area; the painted container stays compact.
    return _ComposerIconButton(
      buttonKey: const ValueKey('voice_button'),
      tooltip: isTranscribing
          ? l.tooltipTranscribingVoiceInput
          : isRecording
          ? l.tooltipStopRecording
          : l.tooltipVoiceInput,
      color: Colors.transparent,
      paintOwnSurface: true,
      onTap: isTranscribing ? null : onTap,
      child: AnimatedContainer(
        duration: motionDuration(context, AppMotion.standard),
        curve: AppMotion.curve,
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isRecording
              ? cs.error
              : isTranscribing
              ? cs.primaryContainer.withValues(alpha: 0.72)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isRecording
                ? cs.error
                : isTranscribing
                ? cs.primary.withValues(alpha: 0.42)
                : cs.outlineVariant.withValues(alpha: 0.32),
          ),
          boxShadow: [
            if (isRecording || isTranscribing)
              BoxShadow(
                color: (isRecording ? cs.error : cs.primary).withValues(
                  alpha: 0.22,
                ),
                blurRadius: 14,
                spreadRadius: 1,
              ),
          ],
        ),
        child: isTranscribing
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              )
            : Icon(
                isRecording ? Icons.stop : Icons.mic,
                size: 18,
                color: isRecording ? cs.onError : cs.primary,
              ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onSend, this.enabled = true});
  final VoidCallback onSend;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    // Solid primary fill (Wave 1 — no gradient); hit area grown to 44px.
    return _ComposerIconButton(
      buttonKey: const ValueKey('send_button'),
      tooltip: l.tooltipSendMessage,
      size: _kComposerActionButtonSize,
      color: cs.primary,
      enabled: enabled,
      onTap: onSend,
      child: Icon(
        Icons.arrow_upward,
        color: cs.onPrimary,
        size: AppIconSize.action,
      ),
    );
  }
}
