import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_itulod/features/rider/presentation/screens/vehicle_documents_screen.dart';
import 'package:app_itulod/shared/models/rider_application_model.dart';

void main() {
  testWidgets('Vehicle & documents shows the details and every document slot', (tester) async {
    const app = RiderApplicationModel(
      id: 'a1',
      riderId: 'r1',
      vehicleType: 'Bicycle',
      vehicleModel: 'Trinx M100',
      status: ApplicationStatus.approved,
      // a bicycle rider: no license / OR-CR, only the selfie and bike photo
      selfieUrl: 'https://x.supabase.co/storage/v1/object/public/rider-documents/r1/selfie.jpg',
      vehicleUrl: 'https://x.supabase.co/storage/v1/object/public/rider-documents/r1/vehicle.jpg',
    );
    await tester.pumpWidget(const MaterialApp(home: VehicleDocumentsScreen(application: app)));
    await tester.pump();

    expect(find.text('Vehicle & documents'), findsOneWidget);
    expect(find.text('Bicycle'), findsOneWidget);
    expect(find.text('Trinx M100'), findsOneWidget);
    for (final label in ["Driver's license", 'OR / CR', 'Selfie', 'Vehicle photo', 'NBI clearance']) {
      expect(find.text(label), findsOneWidget);
    }
    // license, OR/CR and NBI were never uploaded
    expect(find.text('Not uploaded'), findsNWidgets(3));
  });
}
