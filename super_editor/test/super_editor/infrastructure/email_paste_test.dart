import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  const emailAddress = 'xxx@xxx.com';
  final emailUri = Uri(scheme: 'mailto', path: emailAddress);
  const emailWords = {
    'bare address': emailAddress,
    'mailto prefix': 'mailto:xxx@xxx.com',
    'parentheses': '(xxx@xxx.com)',
    'quotes': '"xxx@xxx.com"',
    'label prefix': 'email:xxx@xxx.com',
    'nonbreaking space': '\u00a0xxx@xxx.com',
    'zero-width space': '\u200bxxx@xxx.com',
  };

  group('Email link detection >', () {
    for (final entry in emailWords.entries) {
      test('recognizes an address with ${entry.key}', () {
        expect(tryToParseUrl(entry.value), emailUri);
      });
    }

    test('still recognizes HTTP URLs', () {
      expect(tryToParseUrl('https://example.com'), Uri.parse('https://example.com'));
      expect(tryToParseUrl('example.com'), Uri.parse('https://example.com'));
    });

    test('ignores ordinary text', () {
      expect(tryToParseUrl('contact'), isNull);
    });
  });

  group('Paste with email links >', () {
    for (final entry in emailWords.entries) {
      test('preserves the whole body with ${entry.key}, including undo and redo', () {
        final document = MutableDocument(nodes: [
          ParagraphNode(id: '1', text: AttributedText('Existing text. ')),
        ]);
        final composer = MutableDocumentComposer();
        final editor = createDefaultDocumentEditor(
          document: document,
          composer: composer,
          isHistoryEnabled: true,
        );
        addTearDown(() {
          editor.dispose();
          composer.dispose();
          document.dispose();
        });

        final lines = [
          'First line',
          'Please contact ${entry.value} for details.',
          'Last line',
        ];
        final expectedText = ['Existing text. ${lines.first}', ...lines.skip(1)];

        editor.execute([
          PasteEditorRequest(
            content: lines.join('\n'),
            pastePosition: const DocumentPosition(
              nodeId: '1',
              nodePosition: TextNodePosition(offset: 15),
            ),
            createLinkAttributions: true,
          ),
        ]);

        void expectPastedContent() {
          expect(document.whereType<TextNode>().map((node) => node.text.toPlainText()), expectedText);
          final emailText = (document.getNodeAt(1)! as TextNode).text;
          final emailOffset = emailText.toPlainText().indexOf(emailAddress);
          expect(
            emailText.getAllAttributionsAt(emailOffset).whereType<LinkAttribution>().single.uri,
            emailUri,
          );
          expect(
            composer.selection,
            DocumentSelection.collapsed(
              position: DocumentPosition(nodeId: document.last.id, nodePosition: document.last.endPosition),
            ),
          );
        }

        expectPastedContent();
        final pastedNodeIds = document.map((node) => node.id).toList();

        editor.undo();
        expect(document.length, 1);
        expect((document.first as TextNode).text.toPlainText(), 'Existing text. ');

        editor.redo();
        expectPastedContent();
        expect(document.map((node) => node.id), pastedNodeIds);
      });
    }
  });
}
