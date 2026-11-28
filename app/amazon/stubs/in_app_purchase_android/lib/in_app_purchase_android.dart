// Amazon Appstore build only. The one type lib/services/iap/iap_service.dart
// reads, with the same members. Never made: the stand-in store never
// delivers a purchase.
library;

import 'package:in_app_purchase/in_app_purchase.dart';

class PurchaseWrapper {
  PurchaseWrapper({required this.purchaseToken});

  final String purchaseToken;
}

class GooglePlayPurchaseDetails extends PurchaseDetails {
  GooglePlayPurchaseDetails({
    super.purchaseID,
    required super.productID,
    required super.verificationData,
    required super.transactionDate,
    required this.billingClientPurchase,
    required super.status,
  });

  final PurchaseWrapper billingClientPurchase;
}
