import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart';

void main() {
  test('NoteItem supports nullable preview fields', () {
    const item = NoteItem(
      atomId: 'atom-1',
      content: 'content',
      previewText: null,
      previewImage: null,
      updatedAt: 123,
      tags: ['work'],
    );

    expect(item.previewText, isNull);
    expect(item.previewImage, isNull);
    expect(item.tags, ['work']);
  });

  test('NoteResponse carries preview fields when present', () {
    const note = NoteItem(
      atomId: 'atom-2',
      content: '# title',
      previewText: 'title',
      previewImage: 'cover.png',
      updatedAt: 456,
      tags: ['important', 'work'],
    );
    const response = NoteResponse(
      ok: true,
      errorCode: null,
      message: 'ok',
      note: note,
    );

    expect(response.ok, isTrue);
    expect(response.note, isNotNull);
    expect(response.note!.previewText, 'title');
    expect(response.note!.previewImage, 'cover.png');
  });

  test('NotesListResponse tolerates mixed preview nullability', () {
    const response = NotesListResponse(
      ok: true,
      errorCode: null,
      message: 'Loaded',
      appliedLimit: 10,
      items: [
        NoteItem(
          atomId: 'atom-a',
          content: 'a',
          previewText: 'summary a',
          previewImage: null,
          updatedAt: 1,
          tags: ['work'],
        ),
        NoteItem(
          atomId: 'atom-b',
          content: 'b',
          previewText: null,
          previewImage: 'b.png',
          updatedAt: 2,
          tags: ['home'],
        ),
      ],
    );

    expect(response.ok, isTrue);
    expect(response.items.length, 2);
    expect(response.items[0].previewImage, isNull);
    expect(response.items[1].previewText, isNull);
  });
}
