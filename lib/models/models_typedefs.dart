// lib/models/models_typedefs.dart

import 'ai_history.dart';
import 'chat_message.dart';
import 'family_photo.dart';
import 'list_item.dart';
import 'meal_plan_entry.dart';
import 'period_cycle.dart';
import 'prayer_wall_entry.dart';
import 'special_date.dart';
import 'user_location.dart';

typedef PrayerRequest = PrayerWallEntry;
typedef AIHistoryEntry = AIHistory;
typedef PeriodEntry = PeriodCycle;
typedef LocationShare = UserLocation;
typedef Occasion = SpecialDate;
typedef Photo = FamilyPhoto;
typedef Message = ChatMessage;
typedef ShoppingListItem = ListItem;
typedef MealPlan = MealPlanEntry;
