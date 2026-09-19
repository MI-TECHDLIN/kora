import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../legal_document.dart';

/// A dependency-free viewer for the bundled demo policies.
class LegalDocumentViewer extends StatefulWidget {
  const LegalDocumentViewer({super.key, required this.document});

  final LegalDocument document;

  @override
  State<LegalDocumentViewer> createState() => _LegalDocumentViewerState();
}

class _LegalDocumentViewerState extends State<LegalDocumentViewer> {
  late Future<String> _content = _load();

  Future<String> _load() => rootBundle.loadString(widget.document.assetPath);

  void _retry() => setState(() => _content = _load());

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('legal-document-viewer'),
      color: KoraColors.canvas,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Close ${widget.document.title}',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  TablerIcons.x,
                  size: KoraSize.iconLg,
                  color: KoraColors.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<String>(
                future: _content,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _LoadError(
                      document: widget.document,
                      onRetry: _retry,
                    );
                  }
                  final content = snapshot.data;
                  if (content == null) {
                    return _Loading(document: widget.document);
                  }
                  return _DocumentBody(content: content);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Loading ${document.title}…', style: KoraText.bodyMuted),
          const SizedBox(height: KoraSpacing.lg),
          const CircularProgressIndicator(color: KoraColors.primaryLight),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.document, required this.onRetry});

  final LegalDocument document;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoraSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'We couldn\'t load the ${document.title}.',
              style: KoraText.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KoraSpacing.sm),
            Text(
              'Try again to open the bundled document.',
              style: KoraText.bodyMuted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KoraSpacing.lg),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _DocumentBody extends StatelessWidget {
  const _DocumentBody({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(content);
    return ListView.separated(
      key: const Key('legal-document-content'),
      padding: const EdgeInsets.fromLTRB(
        KoraSpacing.gutter,
        KoraSpacing.sm,
        KoraSpacing.gutter,
        KoraSpacing.xxl,
      ),
      itemCount: blocks.length,
      separatorBuilder: (_, _) => const SizedBox(height: KoraSpacing.lg),
      itemBuilder: (context, index) {
        final block = blocks[index];
        final style = block.isHeading
            ? KoraText.headline
            : KoraText.body;
        return Semantics(
          header: block.isHeading,
          child: SelectableText.rich(
            TextSpan(children: _inlineSpans(block.text, style)),
          ),
        );
      },
    );
  }
}

List<_DocumentBlock> _parseBlocks(String content) {
  final blocks = <_DocumentBlock>[];
  final paragraph = <String>[];

  void flush() {
    if (paragraph.isEmpty) return;
    blocks.add(_DocumentBlock(paragraph.join(' ').trim()));
    paragraph.clear();
  }

  // Strip a trailing \r so a CRLF-checked-out asset (e.g. Windows with
  // core.autocrlf=true) parses the same as the LF the repo stores.
  for (final line in content.replaceAll('\r\n', '\n').split('\n')) {
    if (line.trim().isEmpty) {
      flush();
    } else if (line.startsWith('# ')) {
      flush();
      blocks.add(_DocumentBlock(line.substring(2), isHeading: true));
    } else if (line.startsWith('- ')) {
      flush();
      paragraph.add('• ${line.substring(2)}');
    } else if (line.startsWith('  ') && paragraph.isNotEmpty) {
      paragraph.add(line.trim());
    } else {
      flush();
      paragraph.add(line.trim());
    }
  }
  flush();
  return blocks;
}

List<InlineSpan> _inlineSpans(String text, TextStyle baseStyle) {
  final spans = <InlineSpan>[];
  final emphasis = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*)');
  var cursor = 0;

  for (final match in emphasis.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(text: text.substring(cursor, match.start), style: baseStyle),
      );
    }
    final marked = match.group(0)!;
    if (marked.startsWith('**')) {
      spans.add(
        TextSpan(
          text: marked.substring(2, marked.length - 2),
          style: KoraText.weight(baseStyle, FontWeight.w700),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: marked.substring(1, marked.length - 1),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return spans;
}

class _DocumentBlock {
  const _DocumentBlock(this.text, {this.isHeading = false});

  final String text;
  final bool isHeading;
}
