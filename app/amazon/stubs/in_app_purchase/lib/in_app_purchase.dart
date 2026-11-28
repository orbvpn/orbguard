// Amazon Appstore build only. The part of the API that
// lib/services/iap/iap_service.dart and lib/screens/pricing/pricing_screen.dart
// use, with the same signatures. There is no store: it is never available,
// has no products and never starts a purchase. The Amazon build does not
// start the service or open the pricing screen anyway (kAmazonBuild).
library;

enum PurchaseStatus { pending, purchased, error, restored, canceled }

class IAPError {
  IAPError({
    required this.source,
    required this.code,
    required this.message,
    this.details,
  });

  final String source;
  final String code;
  final String message;
  final dynamic details;
}

class ProductDetails {
  ProductDetails({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.rawPrice,
    required this.currencyCode,
    this.currencySymbol = '',
  });

  final String id;
  final String title;
  final String description;
  final String price;
  final double rawPrice;
  final String currencyCode;
  final String currencySymbol;
}

class ProductDetailsResponse {
  ProductDetailsResponse({
    required this.productDetails,
    required this.notFoundIDs,
    this.error,
  });

  final List<ProductDetails> productDetails;
  final List<String> notFoundIDs;
  final IAPError? error;
}

class PurchaseVerificationData {
  PurchaseVerificationData({
    required this.localVerificationData,
    required this.serverVerificationData,
    required this.source,
  });

  final String localVerificationData;
  final String serverVerificationData;
  final String source;
}

class PurchaseDetails {
  PurchaseDetails({
    this.purchaseID,
    required this.productID,
    required this.verificationData,
    required this.transactionDate,
    required this.status,
  });

  final String? purchaseID;
  final String productID;
  final PurchaseVerificationData verificationData;
  final String? transactionDate;
  PurchaseStatus status;
  IAPError? error;
  bool pendingCompletePurchase = false;
}

class PurchaseParam {
  PurchaseParam({required this.productDetails, this.applicationUserName});

  final ProductDetails productDetails;
  final String? applicationUserName;
}

class InAppPurchase {
  InAppPurchase._();

  static final InAppPurchase instance = InAppPurchase._();

  Stream<List<PurchaseDetails>> get purchaseStream =>
      const Stream<List<PurchaseDetails>>.empty();

  Future<bool> isAvailable() async => false;

  Future<ProductDetailsResponse> queryProductDetails(
          Set<String> identifiers) async =>
      ProductDetailsResponse(
        productDetails: const <ProductDetails>[],
        notFoundIDs: identifiers.toList(),
      );

  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async =>
      false;

  Future<void> completePurchase(PurchaseDetails purchase) async {}

  Future<void> restorePurchases({String? applicationUserName}) async {}
}
