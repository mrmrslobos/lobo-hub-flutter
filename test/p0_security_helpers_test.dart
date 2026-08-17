import 'package:flutter_test/flutter_test.dart';
import 'package:lobohub/services/supabase_service.dart';

void main() {
  group('SupabaseService.familyPhotoStoragePath', () {
    test('parses legacy public URL', () {
      const url =
          'https://example.supabase.co/storage/v1/object/public/family-photos/fam1/photo.jpg';
      expect(
        SupabaseService.familyPhotoStoragePath(url),
        'fam1/photo.jpg',
      );
    });

    test('accepts bare storage path', () {
      expect(
        SupabaseService.familyPhotoStoragePath('fam1/photo.jpg'),
        'fam1/photo.jpg',
      );
    });

    test('returns null for local file path', () {
      expect(SupabaseService.familyPhotoStoragePath('/tmp/photo.jpg'), isNull);
    });
  });
}
