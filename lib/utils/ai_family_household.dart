import '../models/models.dart';

/// How we interpret the AI Family plan (2 adults + 4 under-16) using self-declaration.
/// This is a billing/UX helper — store policy and Terms of Service remain the source of truth.

int countDeclaredAdults(Iterable<FamilyMember> members) =>
    members.where((m) => !m.declaredUnder16).length;

int countDeclaredUnder16(Iterable<FamilyMember> members) =>
    members.where((m) => m.declaredUnder16).length;

const int kAiFamilyAdultSlots = 2;
const int kAiFamilyChildSlots = 4;

/// True when declared counts exceed the marketed AI Family household size.
bool aiFamilyHouseholdOverDeclaredLimits({
  required int adultCount,
  required int under16Count,
}) =>
    adultCount > kAiFamilyAdultSlots || under16Count > kAiFamilyChildSlots;
