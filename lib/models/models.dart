// lib/models/models.dart
// Central model definitions for FamilyHub

import 'dart:convert';

// ─────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────

enum TaskPriority { low, medium, high }

enum TaskRecurrence { none, daily, weekly, monthly }

enum EventVisibility { family, personal }

enum BudgetCategory {
  groceries,
  utilities,
  entertainment,
  dining,
  transport,
  health,
  clothing,
  savings,
  other,
}

enum ChoreFrequency { daily, weekly, monthly, asNeeded }

enum PollStatus { open, closed }

enum MessageType { text, image, system }

// ─────────────────────────────────────────────
// User
// ─────────────────────────────────────────────

class User {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final String? avatarColor;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.avatarColor,
    required this.createdAt,
  });

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? avatarUrl,
    String? avatarColor,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarColor: avatarColor ?? this.avatarColor,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'avatarUrl': avatarUrl,
        'avatarColor': avatarColor,
        'createdAt': createdAt.toIso8601String(),
      };

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        avatarColor: json['avatarColor'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ─────────────────────────────────────────────
// Family
// ─────────────────────────────────────────────

class Family {
  final String id;
  final String name;
  final String joinCode;
  final String ownerId;
  final List<String> enabledModules;
  final String? announcement;
  final DateTime createdAt;

  const Family({
    required this.id,
    required this.name,
    required this.joinCode,
    required this.ownerId,
    required this.enabledModules,
    this.announcement,
    required this.createdAt,
  });

  Family copyWith({
    String? id,
    String? name,
    String? joinCode,
    String? ownerId,
    List<String>? enabledModules,
    String? announcement,
    DateTime? createdAt,
  }) {
    return Family(
      id: id ?? this.id,
      name: name ?? this.name,
      joinCode: joinCode ?? this.joinCode,
      ownerId: ownerId ?? this.ownerId,
      enabledModules: enabledModules ?? this.enabledModules,
      announcement: announcement ?? this.announcement,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'joinCode': joinCode,
        'ownerId': ownerId,
        'enabledModules': enabledModules,
        'announcement': announcement,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Family.fromJson(Map<String, dynamic> json) => Family(
        id: json['id'] as String,
        name: json['name'] as String,
        joinCode: json['joinCode'] as String,
        ownerId: json['ownerId'] as String,
        enabledModules: List<String>.from(json['enabledModules'] as List),
        announcement: json['announcement'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ─────────────────────────────────────────────
// FamilyMember
// ─────────────────────────────────────────────

class FamilyMember {
  final String id;
  final String familyId;
  final String userId;
  final String role; // owner, admin, member
  final DateTime joinedAt;
  // null = all modules accessible; non-null = parental control whitelist
  final List<String>? moduleAccess;

  const FamilyMember({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.moduleAccess,
  });

  FamilyMember copyWith({
    String? id,
    String? familyId,
    String? userId,
    String? role,
    DateTime? joinedAt,
    List<String>? moduleAccess,
    bool clearModuleAccess = false,
  }) =>
      FamilyMember(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        userId: userId ?? this.userId,
        role: role ?? this.role,
        joinedAt: joinedAt ?? this.joinedAt,
        moduleAccess: clearModuleAccess ? null : (moduleAccess ?? this.moduleAccess),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'userId': userId,
        'role': role,
        'joinedAt': joinedAt.toIso8601String(),
        if (moduleAccess != null) 'moduleAccess': moduleAccess,
      };

  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        userId: json['userId'] as String,
        role: json['role'] as String,
        joinedAt: DateTime.parse(json['joinedAt'] as String),
        moduleAccess: (json['moduleAccess'] as List?)?.cast<String>(),
      );
}

// ─────────────────────────────────────────────
// Task
// ─────────────────────────────────────────────

class Task {
  final String id;
  final String familyId;
  final String title;
  final String? notes;
  final bool completed;
  final TaskPriority priority;
  final DateTime? dueDate;
  final List<String> assigneeIds;
  final List<String> tags;
  final TaskRecurrence recurrence;
  final String createdBy;
  final DateTime createdAt;

  const Task({
    required this.id,
    required this.familyId,
    required this.title,
    this.notes,
    required this.completed,
    required this.priority,
    this.dueDate,
    required this.assigneeIds,
    required this.tags,
    required this.recurrence,
    required this.createdBy,
    required this.createdAt,
  });

  Task copyWith({
    String? id,
    String? familyId,
    String? title,
    String? notes,
    bool? completed,
    TaskPriority? priority,
    DateTime? dueDate,
    List<String>? assigneeIds,
    List<String>? tags,
    TaskRecurrence? recurrence,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return Task(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      completed: completed ?? this.completed,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      assigneeIds: assigneeIds ?? this.assigneeIds,
      tags: tags ?? this.tags,
      recurrence: recurrence ?? this.recurrence,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get isOverdue =>
      dueDate != null &&
      !completed &&
      dueDate!.isBefore(DateTime.now().copyWith(
        hour: 0,
        minute: 0,
        second: 0,
        millisecond: 0,
      ));

  bool get isDueToday {
    if (dueDate == null) return false;
    final now = DateTime.now();
    return dueDate!.year == now.year &&
        dueDate!.month == now.month &&
        dueDate!.day == now.day;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'title': title,
        'notes': notes,
        'completed': completed,
        'priority': priority.name,
        'dueDate': dueDate?.toIso8601String(),
        'assigneeIds': assigneeIds,
        'tags': tags,
        'recurrence': recurrence.name,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        title: json['title'] as String,
        notes: json['notes'] as String?,
        completed: json['completed'] as bool,
        priority: TaskPriority.values.firstWhere(
          (e) => e.name == json['priority'],
          orElse: () => TaskPriority.medium,
        ),
        dueDate: json['dueDate'] != null
            ? DateTime.parse(json['dueDate'] as String)
            : null,
        assigneeIds: List<String>.from(json['assigneeIds'] as List),
        tags: List<String>.from(json['tags'] as List),
        recurrence: TaskRecurrence.values.firstWhere(
          (e) => e.name == json['recurrence'],
          orElse: () => TaskRecurrence.none,
        ),
        createdBy: json['createdBy'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ─────────────────────────────────────────────
// CalendarEvent
// ─────────────────────────────────────────────

class CalendarEvent {
  final String id;
  final String familyId;
  final String title;
  final String? description;
  final String? location;
  final DateTime startDate;
  final DateTime endDate;
  final bool allDay;
  final EventVisibility visibility;
  final String createdBy;
  final String? color;
  final DateTime createdAt;

  const CalendarEvent({
    required this.id,
    required this.familyId,
    required this.title,
    this.description,
    this.location,
    required this.startDate,
    required this.endDate,
    required this.allDay,
    required this.visibility,
    required this.createdBy,
    this.color,
    required this.createdAt,
  });

  CalendarEvent copyWith({
    String? id,
    String? familyId,
    String? title,
    String? description,
    String? location,
    DateTime? startDate,
    DateTime? endDate,
    bool? allDay,
    EventVisibility? visibility,
    String? createdBy,
    String? color,
    DateTime? createdAt,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      allDay: allDay ?? this.allDay,
      visibility: visibility ?? this.visibility,
      createdBy: createdBy ?? this.createdBy,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'title': title,
        'description': description,
        'location': location,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'allDay': allDay,
        'visibility': visibility.name,
        'createdBy': createdBy,
        'color': color,
        'createdAt': createdAt.toIso8601String(),
      };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        location: json['location'] as String?,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        allDay: json['allDay'] as bool,
        visibility: EventVisibility.values.firstWhere(
          (e) => e.name == json['visibility'],
          orElse: () => EventVisibility.family,
        ),
        createdBy: json['createdBy'] as String,
        color: json['color'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ─────────────────────────────────────────────
// Message
// ─────────────────────────────────────────────

class Message {
  final String id;
  final String familyId;
  final String senderId;
  final String content;
  final MessageType type;
  final String? replyToId;
  final Map<String, List<String>> reactions; // emoji -> userIds
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.familyId,
    required this.senderId,
    required this.content,
    required this.type,
    this.replyToId,
    required this.reactions,
    required this.createdAt,
  });

  Message copyWith({
    String? id,
    String? familyId,
    String? senderId,
    String? content,
    MessageType? type,
    String? replyToId,
    Map<String, List<String>>? reactions,
    DateTime? createdAt,
  }) {
    return Message(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      type: type ?? this.type,
      replyToId: replyToId ?? this.replyToId,
      reactions: reactions ?? this.reactions,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'senderId': senderId,
        'content': content,
        'type': type.name,
        'replyToId': replyToId,
        'reactions': reactions.map(
          (key, value) => MapEntry(key, value),
        ),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        senderId: json['senderId'] as String,
        content: json['content'] as String,
        type: MessageType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => MessageType.text,
        ),
        replyToId: json['replyToId'] as String?,
        reactions: (json['reactions'] as Map<String, dynamic>?)?.map(
              (key, value) =>
                  MapEntry(key, List<String>.from(value as List)),
            ) ??
            {},
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ─────────────────────────────────────────────
// Chore
// ─────────────────────────────────────────────

class Chore {
  final String id;
  final String familyId;
  final String title;
  final String? description;
  final List<String> assigneeIds;
  final ChoreFrequency frequency;
  final int points;
  final DateTime? lastCompletedAt;
  final String? lastCompletedBy;
  final DateTime createdAt;

  const Chore({
    required this.id,
    required this.familyId,
    required this.title,
    this.description,
    required this.assigneeIds,
    required this.frequency,
    required this.points,
    this.lastCompletedAt,
    this.lastCompletedBy,
    required this.createdAt,
  });

  Chore copyWith({
    String? id,
    String? familyId,
    String? title,
    String? description,
    List<String>? assigneeIds,
    ChoreFrequency? frequency,
    int? points,
    DateTime? lastCompletedAt,
    String? lastCompletedBy,
    DateTime? createdAt,
  }) {
    return Chore(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      title: title ?? this.title,
      description: description ?? this.description,
      assigneeIds: assigneeIds ?? this.assigneeIds,
      frequency: frequency ?? this.frequency,
      points: points ?? this.points,
      lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
      lastCompletedBy: lastCompletedBy ?? this.lastCompletedBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'title': title,
        'description': description,
        'assigneeIds': assigneeIds,
        'frequency': frequency.name,
        'points': points,
        'lastCompletedAt': lastCompletedAt?.toIso8601String(),
        'lastCompletedBy': lastCompletedBy,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Chore.fromJson(Map<String, dynamic> json) => Chore(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        assigneeIds: List<String>.from(json['assigneeIds'] as List),
        frequency: ChoreFrequency.values.firstWhere(
          (e) => e.name == json['frequency'],
          orElse: () => ChoreFrequency.weekly,
        ),
        points: json['points'] as int,
        lastCompletedAt: json['lastCompletedAt'] != null
            ? DateTime.parse(json['lastCompletedAt'] as String)
            : null,
        lastCompletedBy: json['lastCompletedBy'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ─────────────────────────────────────────────
// ShoppingList / ListItem
// ─────────────────────────────────────────────

class ShoppingList {
  final String id;
  final String familyId;
  final String name;
  final List<ListItem> items;
  final String createdBy;
  final DateTime createdAt;

  const ShoppingList({
    required this.id,
    required this.familyId,
    required this.name,
    required this.items,
    required this.createdBy,
    required this.createdAt,
  });

  ShoppingList copyWith({
    String? id,
    String? familyId,
    String? name,
    List<ListItem>? items,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return ShoppingList(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      name: name ?? this.name,
      items: items ?? this.items,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'name': name,
        'items': items.map((e) => e.toJson()).toList(),
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ShoppingList.fromJson(Map<String, dynamic> json) => ShoppingList(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        name: json['name'] as String,
        items: (json['items'] as List)
            .map((e) => ListItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdBy: json['createdBy'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class ListItem {
  final String id;
  final String name;
  final bool checked;
  final int quantity;
  final String? note;

  const ListItem({
    required this.id,
    required this.name,
    required this.checked,
    required this.quantity,
    this.note,
  });

  ListItem copyWith({
    String? id,
    String? name,
    bool? checked,
    int? quantity,
    String? note,
  }) {
    return ListItem(
      id: id ?? this.id,
      name: name ?? this.name,
      checked: checked ?? this.checked,
      quantity: quantity ?? this.quantity,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'checked': checked,
        'quantity': quantity,
        'note': note,
      };

  factory ListItem.fromJson(Map<String, dynamic> json) => ListItem(
        id: json['id'] as String,
        name: json['name'] as String,
        checked: json['checked'] as bool,
        quantity: json['quantity'] as int? ?? 1,
        note: json['note'] as String?,
      );
}

// ─────────────────────────────────────────────
// MealPlan
// ─────────────────────────────────────────────

class MealPlan {
  final String id;
  final String familyId;
  final DateTime date;
  final String mealType; // breakfast, lunch, dinner, snack
  final String title;
  final String? notes;
  final String createdBy;

  const MealPlan({
    required this.id,
    required this.familyId,
    required this.date,
    required this.mealType,
    required this.title,
    this.notes,
    required this.createdBy,
  });

  MealPlan copyWith({
    String? id,
    String? familyId,
    DateTime? date,
    String? mealType,
    String? title,
    String? notes,
    String? createdBy,
  }) {
    return MealPlan(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      date: date ?? this.date,
      mealType: mealType ?? this.mealType,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'date': date.toIso8601String(),
        'mealType': mealType,
        'title': title,
        'notes': notes,
        'createdBy': createdBy,
      };

  factory MealPlan.fromJson(Map<String, dynamic> json) => MealPlan(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        date: DateTime.parse(json['date'] as String),
        mealType: json['mealType'] as String,
        title: json['title'] as String,
        notes: json['notes'] as String?,
        createdBy: json['createdBy'] as String,
      );
}

// ─────────────────────────────────────────────
// BudgetEntry
// ─────────────────────────────────────────────

class BudgetEntry {
  final String id;
  final String familyId;
  final String title;
  final double amount;
  final BudgetCategory category;
  final bool isIncome;
  final DateTime date;
  final String createdBy;
  final String? notes;

  const BudgetEntry({
    required this.id,
    required this.familyId,
    required this.title,
    required this.amount,
    required this.category,
    required this.isIncome,
    required this.date,
    required this.createdBy,
    this.notes,
  });

  BudgetEntry copyWith({
    String? id,
    String? familyId,
    String? title,
    double? amount,
    BudgetCategory? category,
    bool? isIncome,
    DateTime? date,
    String? createdBy,
    String? notes,
  }) {
    return BudgetEntry(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      isIncome: isIncome ?? this.isIncome,
      date: date ?? this.date,
      createdBy: createdBy ?? this.createdBy,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'title': title,
        'amount': amount,
        'category': category.name,
        'isIncome': isIncome,
        'date': date.toIso8601String(),
        'createdBy': createdBy,
        'notes': notes,
      };

  factory BudgetEntry.fromJson(Map<String, dynamic> json) => BudgetEntry(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        title: json['title'] as String,
        amount: (json['amount'] as num).toDouble(),
        category: BudgetCategory.values.firstWhere(
          (e) => e.name == json['category'],
          orElse: () => BudgetCategory.other,
        ),
        isIncome: json['isIncome'] as bool,
        date: DateTime.parse(json['date'] as String),
        createdBy: json['createdBy'] as String,
        notes: json['notes'] as String?,
      );
}

// ─────────────────────────────────────────────
// Reward
// ─────────────────────────────────────────────

class Reward {
  final String id;
  final String familyId;
  final String title;
  final int pointCost;
  final String? description;
  final List<String> redeemedBy; // userId list

  const Reward({
    required this.id,
    required this.familyId,
    required this.title,
    required this.pointCost,
    this.description,
    required this.redeemedBy,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'title': title,
        'pointCost': pointCost,
        'description': description,
        'redeemedBy': redeemedBy,
      };

  factory Reward.fromJson(Map<String, dynamic> json) => Reward(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        title: json['title'] as String,
        pointCost: json['pointCost'] as int,
        description: json['description'] as String?,
        redeemedBy: List<String>.from(json['redeemedBy'] as List),
      );
}

// ─────────────────────────────────────────────
// Poll
// ─────────────────────────────────────────────

class Poll {
  final String id;
  final String familyId;
  final String question;
  final List<PollOption> options;
  final PollStatus status;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const Poll({
    required this.id,
    required this.familyId,
    required this.question,
    required this.options,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.expiresAt,
  });

  Poll copyWith({
    String? id,
    String? familyId,
    String? question,
    List<PollOption>? options,
    PollStatus? status,
    String? createdBy,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    return Poll(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      question: question ?? this.question,
      options: options ?? this.options,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  int get totalVotes => options.fold(0, (sum, o) => sum + o.voterIds.length);

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'question': question,
        'options': options.map((e) => e.toJson()).toList(),
        'status': status.name,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
      };

  factory Poll.fromJson(Map<String, dynamic> json) => Poll(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        question: json['question'] as String,
        options: (json['options'] as List)
            .map((e) => PollOption.fromJson(e as Map<String, dynamic>))
            .toList(),
        status: PollStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => PollStatus.open,
        ),
        createdBy: json['createdBy'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
            : null,
      );
}

class PollOption {
  final String id;
  final String text;
  final List<String> voterIds;

  const PollOption({
    required this.id,
    required this.text,
    required this.voterIds,
  });

  PollOption copyWith({
    String? id,
    String? text,
    List<String>? voterIds,
  }) {
    return PollOption(
      id: id ?? this.id,
      text: text ?? this.text,
      voterIds: voterIds ?? this.voterIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'voterIds': voterIds,
      };

  factory PollOption.fromJson(Map<String, dynamic> json) => PollOption(
        id: json['id'] as String,
        text: json['text'] as String,
        voterIds: List<String>.from(json['voterIds'] as List),
      );
}

// ─────────────────────────────────────────────
// FitnessLog
// ─────────────────────────────────────────────

class FitnessLog {
  final String id;
  final String familyId;
  final String userId;
  final String activity;
  final int durationMinutes;
  final int? caloriesBurned;
  final String? notes;
  final DateTime date;

  const FitnessLog({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.activity,
    required this.durationMinutes,
    this.caloriesBurned,
    this.notes,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'userId': userId,
        'activity': activity,
        'durationMinutes': durationMinutes,
        'caloriesBurned': caloriesBurned,
        'notes': notes,
        'date': date.toIso8601String(),
      };

  factory FitnessLog.fromJson(Map<String, dynamic> json) => FitnessLog(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        userId: json['userId'] as String,
        activity: json['activity'] as String,
        durationMinutes: json['durationMinutes'] as int,
        caloriesBurned: json['caloriesBurned'] as int?,
        notes: json['notes'] as String?,
        date: DateTime.parse(json['date'] as String),
      );
}

// ─────────────────────────────────────────────
// PrayerRequest
// ─────────────────────────────────────────────

class PrayerRequest {
  final String id;
  final String familyId;
  final String userId;
  final String title;
  final String? body;
  final bool answered;
  final List<String> prayedByIds;
  final DateTime createdAt;

  const PrayerRequest({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.title,
    this.body,
    required this.answered,
    required this.prayedByIds,
    required this.createdAt,
  });

  PrayerRequest copyWith({
    String? id,
    String? familyId,
    String? userId,
    String? title,
    String? body,
    bool? answered,
    List<String>? prayedByIds,
    DateTime? createdAt,
  }) {
    return PrayerRequest(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      body: body ?? this.body,
      answered: answered ?? this.answered,
      prayedByIds: prayedByIds ?? this.prayedByIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'userId': userId,
        'title': title,
        'body': body,
        'answered': answered,
        'prayedByIds': prayedByIds,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PrayerRequest.fromJson(Map<String, dynamic> json) => PrayerRequest(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        userId: json['userId'] as String,
        title: json['title'] as String,
        body: json['body'] as String?,
        answered: json['answered'] as bool,
        prayedByIds: List<String>.from(json['prayedByIds'] as List),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ─────────────────────────────────────────────
// Occasion (Birthday / Anniversary)
// ─────────────────────────────────────────────

class Occasion {
  final String id;
  final String familyId;
  final String title;
  final String type; // birthday, anniversary, holiday, custom
  final DateTime date;
  final bool recurring;
  final String? notes;

  const Occasion({
    required this.id,
    required this.familyId,
    required this.title,
    required this.type,
    required this.date,
    required this.recurring,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'title': title,
        'type': type,
        'date': date.toIso8601String(),
        'recurring': recurring,
        'notes': notes,
      };

  factory Occasion.fromJson(Map<String, dynamic> json) => Occasion(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        title: json['title'] as String,
        type: json['type'] as String,
        date: DateTime.parse(json['date'] as String),
        recurring: json['recurring'] as bool,
        notes: json['notes'] as String?,
      );
}

// ─────────────────────────────────────────────
// HealthRecord
// ─────────────────────────────────────────────

class HealthRecord {
  final String id;
  final String familyId;
  final String userId;
  final String type; // weight, blood_pressure, medication, appointment, note
  final String title;
  final Map<String, dynamic> data;
  final DateTime date;
  final String? notes;

  const HealthRecord({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.type,
    required this.title,
    required this.data,
    required this.date,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'userId': userId,
        'type': type,
        'title': title,
        'data': data,
        'date': date.toIso8601String(),
        'notes': notes,
      };

  factory HealthRecord.fromJson(Map<String, dynamic> json) => HealthRecord(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        userId: json['userId'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
        data: Map<String, dynamic>.from(json['data'] as Map),
        date: DateTime.parse(json['date'] as String),
        notes: json['notes'] as String?,
      );
}

// ─────────────────────────────────────────────
// PeriodEntry
// ─────────────────────────────────────────────

class PeriodEntry {
  final String id;
  final String familyId;
  final String userId;
  final DateTime startDate;
  final DateTime? endDate;
  final int? flowLevel; // 1-5
  final List<String> symptoms;
  final String? notes;

  const PeriodEntry({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.startDate,
    this.endDate,
    this.flowLevel,
    required this.symptoms,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'userId': userId,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'flowLevel': flowLevel,
        'symptoms': symptoms,
        'notes': notes,
      };

  factory PeriodEntry.fromJson(Map<String, dynamic> json) => PeriodEntry(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        userId: json['userId'] as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: json['endDate'] != null
            ? DateTime.parse(json['endDate'] as String)
            : null,
        flowLevel: json['flowLevel'] as int?,
        symptoms: List<String>.from(json['symptoms'] as List),
        notes: json['notes'] as String?,
      );
}

// ─────────────────────────────────────────────
// DevotionalEntry
// ─────────────────────────────────────────────

class DevotionalEntry {
  final String id;
  final String familyId;
  final String userId;
  final String title;
  final String content;
  final String? scripture;
  final DateTime date;

  const DevotionalEntry({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.title,
    required this.content,
    this.scripture,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'userId': userId,
        'title': title,
        'content': content,
        'scripture': scripture,
        'date': date.toIso8601String(),
      };

  factory DevotionalEntry.fromJson(Map<String, dynamic> json) =>
      DevotionalEntry(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        userId: json['userId'] as String,
        title: json['title'] as String,
        content: json['content'] as String,
        scripture: json['scripture'] as String?,
        date: DateTime.parse(json['date'] as String),
      );
}

// ─────────────────────────────────────────────
// Photo
// ─────────────────────────────────────────────

class Photo {
  final String id;
  final String familyId;
  final String uploadedBy;
  final String url;
  final String? thumbnailUrl;
  final String? caption;
  final List<String> tags;
  final DateTime createdAt;

  const Photo({
    required this.id,
    required this.familyId,
    required this.uploadedBy,
    required this.url,
    this.thumbnailUrl,
    this.caption,
    required this.tags,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'uploadedBy': uploadedBy,
        'url': url,
        'thumbnailUrl': thumbnailUrl,
        'caption': caption,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Photo.fromJson(Map<String, dynamic> json) => Photo(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        uploadedBy: json['uploadedBy'] as String,
        url: json['url'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        caption: json['caption'] as String?,
        tags: List<String>.from(json['tags'] as List),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ─────────────────────────────────────────────
// LocationShare
// ─────────────────────────────────────────────

class LocationShare {
  final String id;
  final String familyId;
  final String userId;
  final double latitude;
  final double longitude;
  final String? address;
  final DateTime updatedAt;
  final bool isSharing;

  const LocationShare({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.updatedAt,
    required this.isSharing,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'userId': userId,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'updatedAt': updatedAt.toIso8601String(),
        'isSharing': isSharing,
      };

  factory LocationShare.fromJson(Map<String, dynamic> json) => LocationShare(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        userId: json['userId'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        address: json['address'] as String?,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        isSharing: json['isSharing'] as bool,
      );
}

// ─────────────────────────────────────────────
// AIHistoryEntry
// ─────────────────────────────────────────────

class AIHistoryEntry {
  final String id;
  final String familyId;
  final String userId;
  final String prompt;
  final String response;
  final String module;
  final DateTime createdAt;

  const AIHistoryEntry({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.prompt,
    required this.response,
    required this.module,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'userId': userId,
        'prompt': prompt,
        'response': response,
        'module': module,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AIHistoryEntry.fromJson(Map<String, dynamic> json) => AIHistoryEntry(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        userId: json['userId'] as String,
        prompt: json['prompt'] as String,
        response: json['response'] as String,
        module: json['module'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ─────────────────────────────────────────────
// AppDB — root data container
// ─────────────────────────────────────────────

class AppDB {
  final List<User> users;
  final List<Family> families;
  final List<FamilyMember> familyMembers;
  final List<Task> tasks;
  final List<CalendarEvent> events;
  final List<Message> messages;
  final List<Chore> chores;
  final List<ShoppingList> shoppingLists;
  final List<MealPlan> mealPlans;
  final List<BudgetEntry> budgetEntries;
  final List<Reward> rewards;
  final List<Poll> polls;
  final List<FitnessLog> fitnessLogs;
  final List<PrayerRequest> prayerRequests;
  final List<Occasion> occasions;
  final List<HealthRecord> healthRecords;
  final List<PeriodEntry> periodEntries;
  final List<DevotionalEntry> devotionalEntries;
  final List<Photo> photos;
  final List<LocationShare> locationShares;
  final List<AIHistoryEntry> aiHistory;
  final List<Recipe> recipes;
  final List<SavingsGoal> savingsGoals;
  final List<DailyHabit> dailyHabits;
  final List<DailyHabitCompletion> habitCompletions;
  final List<ReadingPlan> readingPlans;

  const AppDB({
    this.users = const [],
    this.families = const [],
    this.familyMembers = const [],
    this.tasks = const [],
    this.events = const [],
    this.messages = const [],
    this.chores = const [],
    this.shoppingLists = const [],
    this.mealPlans = const [],
    this.budgetEntries = const [],
    this.rewards = const [],
    this.polls = const [],
    this.fitnessLogs = const [],
    this.prayerRequests = const [],
    this.occasions = const [],
    this.healthRecords = const [],
    this.periodEntries = const [],
    this.devotionalEntries = const [],
    this.photos = const [],
    this.locationShares = const [],
    this.aiHistory = const [],
    this.recipes = const [],
    this.savingsGoals = const [],
    this.dailyHabits = const [],
    this.habitCompletions = const [],
    this.readingPlans = const [],
  });

  AppDB copyWith({
    List<User>? users,
    List<Family>? families,
    List<FamilyMember>? familyMembers,
    List<Task>? tasks,
    List<CalendarEvent>? events,
    List<Message>? messages,
    List<Chore>? chores,
    List<ShoppingList>? shoppingLists,
    List<MealPlan>? mealPlans,
    List<BudgetEntry>? budgetEntries,
    List<Reward>? rewards,
    List<Poll>? polls,
    List<FitnessLog>? fitnessLogs,
    List<PrayerRequest>? prayerRequests,
    List<Occasion>? occasions,
    List<HealthRecord>? healthRecords,
    List<PeriodEntry>? periodEntries,
    List<DevotionalEntry>? devotionalEntries,
    List<Photo>? photos,
    List<LocationShare>? locationShares,
    List<AIHistoryEntry>? aiHistory,
    List<Recipe>? recipes,
    List<SavingsGoal>? savingsGoals,
    List<DailyHabit>? dailyHabits,
    List<DailyHabitCompletion>? habitCompletions,
    List<ReadingPlan>? readingPlans,
  }) {
    return AppDB(
      users: users ?? this.users,
      families: families ?? this.families,
      familyMembers: familyMembers ?? this.familyMembers,
      tasks: tasks ?? this.tasks,
      events: events ?? this.events,
      messages: messages ?? this.messages,
      chores: chores ?? this.chores,
      shoppingLists: shoppingLists ?? this.shoppingLists,
      mealPlans: mealPlans ?? this.mealPlans,
      budgetEntries: budgetEntries ?? this.budgetEntries,
      rewards: rewards ?? this.rewards,
      polls: polls ?? this.polls,
      fitnessLogs: fitnessLogs ?? this.fitnessLogs,
      prayerRequests: prayerRequests ?? this.prayerRequests,
      occasions: occasions ?? this.occasions,
      healthRecords: healthRecords ?? this.healthRecords,
      periodEntries: periodEntries ?? this.periodEntries,
      devotionalEntries: devotionalEntries ?? this.devotionalEntries,
      photos: photos ?? this.photos,
      locationShares: locationShares ?? this.locationShares,
      aiHistory: aiHistory ?? this.aiHistory,
      recipes: recipes ?? this.recipes,
      savingsGoals: savingsGoals ?? this.savingsGoals,
      dailyHabits: dailyHabits ?? this.dailyHabits,
      habitCompletions: habitCompletions ?? this.habitCompletions,
      readingPlans: readingPlans ?? this.readingPlans,
    );
  }

  Map<String, dynamic> toJson() => {
        'users': users.map((e) => e.toJson()).toList(),
        'families': families.map((e) => e.toJson()).toList(),
        'familyMembers': familyMembers.map((e) => e.toJson()).toList(),
        'tasks': tasks.map((e) => e.toJson()).toList(),
        'events': events.map((e) => e.toJson()).toList(),
        'messages': messages.map((e) => e.toJson()).toList(),
        'chores': chores.map((e) => e.toJson()).toList(),
        'shoppingLists': shoppingLists.map((e) => e.toJson()).toList(),
        'mealPlans': mealPlans.map((e) => e.toJson()).toList(),
        'budgetEntries': budgetEntries.map((e) => e.toJson()).toList(),
        'rewards': rewards.map((e) => e.toJson()).toList(),
        'polls': polls.map((e) => e.toJson()).toList(),
        'fitnessLogs': fitnessLogs.map((e) => e.toJson()).toList(),
        'prayerRequests': prayerRequests.map((e) => e.toJson()).toList(),
        'occasions': occasions.map((e) => e.toJson()).toList(),
        'healthRecords': healthRecords.map((e) => e.toJson()).toList(),
        'periodEntries': periodEntries.map((e) => e.toJson()).toList(),
        'devotionalEntries':
            devotionalEntries.map((e) => e.toJson()).toList(),
        'photos': photos.map((e) => e.toJson()).toList(),
        'locationShares': locationShares.map((e) => e.toJson()).toList(),
        'aiHistory': aiHistory.map((e) => e.toJson()).toList(),
        'recipes': recipes.map((e) => e.toJson()).toList(),
        'savingsGoals': savingsGoals.map((e) => e.toJson()).toList(),
        'dailyHabits': dailyHabits.map((e) => e.toJson()).toList(),
        'habitCompletions': habitCompletions.map((e) => e.toJson()).toList(),
        'readingPlans': readingPlans.map((e) => e.toJson()).toList(),
      };

  factory AppDB.fromJson(Map<String, dynamic> json) => AppDB(
        users: (json['users'] as List? ?? [])
            .map((e) => User.fromJson(e as Map<String, dynamic>))
            .toList(),
        families: (json['families'] as List? ?? [])
            .map((e) => Family.fromJson(e as Map<String, dynamic>))
            .toList(),
        familyMembers: (json['familyMembers'] as List? ?? [])
            .map((e) => FamilyMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        tasks: (json['tasks'] as List? ?? [])
            .map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList(),
        events: (json['events'] as List? ?? [])
            .map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        messages: (json['messages'] as List? ?? [])
            .map((e) => Message.fromJson(e as Map<String, dynamic>))
            .toList(),
        chores: (json['chores'] as List? ?? [])
            .map((e) => Chore.fromJson(e as Map<String, dynamic>))
            .toList(),
        shoppingLists: (json['shoppingLists'] as List? ?? [])
            .map((e) => ShoppingList.fromJson(e as Map<String, dynamic>))
            .toList(),
        mealPlans: (json['mealPlans'] as List? ?? [])
            .map((e) => MealPlan.fromJson(e as Map<String, dynamic>))
            .toList(),
        budgetEntries: (json['budgetEntries'] as List? ?? [])
            .map((e) => BudgetEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        rewards: (json['rewards'] as List? ?? [])
            .map((e) => Reward.fromJson(e as Map<String, dynamic>))
            .toList(),
        polls: (json['polls'] as List? ?? [])
            .map((e) => Poll.fromJson(e as Map<String, dynamic>))
            .toList(),
        fitnessLogs: (json['fitnessLogs'] as List? ?? [])
            .map((e) => FitnessLog.fromJson(e as Map<String, dynamic>))
            .toList(),
        prayerRequests: (json['prayerRequests'] as List? ?? [])
            .map((e) => PrayerRequest.fromJson(e as Map<String, dynamic>))
            .toList(),
        occasions: (json['occasions'] as List? ?? [])
            .map((e) => Occasion.fromJson(e as Map<String, dynamic>))
            .toList(),
        healthRecords: (json['healthRecords'] as List? ?? [])
            .map((e) => HealthRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
        periodEntries: (json['periodEntries'] as List? ?? [])
            .map((e) => PeriodEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        devotionalEntries: (json['devotionalEntries'] as List? ?? [])
            .map((e) => DevotionalEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        photos: (json['photos'] as List? ?? [])
            .map((e) => Photo.fromJson(e as Map<String, dynamic>))
            .toList(),
        locationShares: (json['locationShares'] as List? ?? [])
            .map((e) => LocationShare.fromJson(e as Map<String, dynamic>))
            .toList(),
        aiHistory: (json['aiHistory'] as List? ?? [])
            .map((e) => AIHistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        recipes: (json['recipes'] as List? ?? [])
            .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
            .toList(),
        savingsGoals: (json['savingsGoals'] as List? ?? [])
            .map((e) => SavingsGoal.fromJson(e as Map<String, dynamic>))
            .toList(),
        dailyHabits: (json['dailyHabits'] as List? ?? [])
            .map((e) => DailyHabit.fromJson(e as Map<String, dynamic>))
            .toList(),
        habitCompletions: (json['habitCompletions'] as List? ?? [])
            .map((e) => DailyHabitCompletion.fromJson(e as Map<String, dynamic>))
            .toList(),
        readingPlans: (json['readingPlans'] as List? ?? [])
            .map((e) => ReadingPlan.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  factory AppDB.empty() => const AppDB();

  String toJsonString() => jsonEncode(toJson());

  factory AppDB.fromJsonString(String source) =>
      AppDB.fromJson(jsonDecode(source) as Map<String, dynamic>);
}

// ─────────────────────────────────────────────
// Recipe
// ─────────────────────────────────────────────

class RecipeIngredient {
  final String name;
  final String amount;
  final String? unit;

  const RecipeIngredient({required this.name, required this.amount, this.unit});

  Map<String, dynamic> toJson() => {'name': name, 'amount': amount, if (unit != null) 'unit': unit};

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) => RecipeIngredient(
        name: json['name'] as String,
        amount: json['amount'] as String,
        unit: json['unit'] as String?,
      );
}

class Recipe {
  final String id;
  final String familyId;
  final String title;
  final String? description;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;
  final int? prepMinutes;
  final int? cookMinutes;
  final int? servings;
  final List<String> tags;
  final String? imageUrl;
  final String? sourceUrl;
  final String createdBy;
  final DateTime createdAt;

  const Recipe({
    required this.id,
    required this.familyId,
    required this.title,
    this.description,
    this.ingredients = const [],
    this.steps = const [],
    this.prepMinutes,
    this.cookMinutes,
    this.servings,
    this.tags = const [],
    this.imageUrl,
    this.sourceUrl,
    required this.createdBy,
    required this.createdAt,
  });

  Recipe copyWith({
    String? id,
    String? familyId,
    String? title,
    String? description,
    List<RecipeIngredient>? ingredients,
    List<String>? steps,
    int? prepMinutes,
    int? cookMinutes,
    int? servings,
    List<String>? tags,
    String? imageUrl,
    String? sourceUrl,
    String? createdBy,
    DateTime? createdAt,
  }) =>
      Recipe(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        title: title ?? this.title,
        description: description ?? this.description,
        ingredients: ingredients ?? this.ingredients,
        steps: steps ?? this.steps,
        prepMinutes: prepMinutes ?? this.prepMinutes,
        cookMinutes: cookMinutes ?? this.cookMinutes,
        servings: servings ?? this.servings,
        tags: tags ?? this.tags,
        imageUrl: imageUrl ?? this.imageUrl,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        createdBy: createdBy ?? this.createdBy,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'title': title,
        if (description != null) 'description': description,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
        'steps': steps,
        if (prepMinutes != null) 'prepMinutes': prepMinutes,
        if (cookMinutes != null) 'cookMinutes': cookMinutes,
        if (servings != null) 'servings': servings,
        'tags': tags,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        ingredients: (json['ingredients'] as List? ?? [])
            .map((e) => RecipeIngredient.fromJson(e as Map<String, dynamic>))
            .toList(),
        steps: (json['steps'] as List? ?? []).cast<String>(),
        prepMinutes: json['prepMinutes'] as int?,
        cookMinutes: json['cookMinutes'] as int?,
        servings: json['servings'] as int?,
        tags: (json['tags'] as List? ?? []).cast<String>(),
        imageUrl: json['imageUrl'] as String?,
        sourceUrl: json['sourceUrl'] as String?,
        createdBy: json['createdBy'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ─────────────────────────────────────────────
// SavingsGoal
// ─────────────────────────────────────────────

class SavingsGoal {
  final String id;
  final String familyId;
  final String title;
  final double targetAmount;
  final double currentAmount;
  final String? emoji;
  final DateTime? deadline;
  final String createdBy;
  final DateTime createdAt;

  const SavingsGoal({
    required this.id,
    required this.familyId,
    required this.title,
    required this.targetAmount,
    this.currentAmount = 0,
    this.emoji,
    this.deadline,
    required this.createdBy,
    required this.createdAt,
  });

  double get progress => targetAmount > 0 ? (currentAmount / targetAmount).clamp(0, 1) : 0;
  bool get isComplete => currentAmount >= targetAmount;

  SavingsGoal copyWith({
    String? id,
    String? familyId,
    String? title,
    double? targetAmount,
    double? currentAmount,
    String? emoji,
    DateTime? deadline,
    String? createdBy,
    DateTime? createdAt,
  }) =>
      SavingsGoal(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        title: title ?? this.title,
        targetAmount: targetAmount ?? this.targetAmount,
        currentAmount: currentAmount ?? this.currentAmount,
        emoji: emoji ?? this.emoji,
        deadline: deadline ?? this.deadline,
        createdBy: createdBy ?? this.createdBy,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'title': title,
        'targetAmount': targetAmount,
        'currentAmount': currentAmount,
        if (emoji != null) 'emoji': emoji,
        if (deadline != null) 'deadline': deadline!.toIso8601String(),
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavingsGoal.fromJson(Map<String, dynamic> json) => SavingsGoal(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        title: json['title'] as String,
        targetAmount: (json['targetAmount'] as num).toDouble(),
        currentAmount: (json['currentAmount'] as num? ?? 0).toDouble(),
        emoji: json['emoji'] as String?,
        deadline: json['deadline'] != null ? DateTime.parse(json['deadline'] as String) : null,
        createdBy: json['createdBy'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ─────────────────────────────────────────────
// DailyHabit
// ─────────────────────────────────────────────

class DailyHabit {
  final String id;
  final String familyId;
  final String userId; // owner
  final String title;
  final String? description;
  final String emoji;
  final String frequency; // daily, weekdays, weekends, custom
  final List<int> customDays; // 1=Mon…7=Sun, used when frequency=='custom'
  final bool isShared; // visible to family
  final String? targetUnit; // e.g. 'minutes', 'glasses', null
  final int? targetValue;
  final DateTime createdAt;

  const DailyHabit({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.title,
    this.description,
    this.emoji = '✅',
    this.frequency = 'daily',
    this.customDays = const [],
    this.isShared = false,
    this.targetUnit,
    this.targetValue,
    required this.createdAt,
  });

  DailyHabit copyWith({
    String? id,
    String? familyId,
    String? userId,
    String? title,
    String? description,
    String? emoji,
    String? frequency,
    List<int>? customDays,
    bool? isShared,
    String? targetUnit,
    int? targetValue,
    DateTime? createdAt,
  }) =>
      DailyHabit(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        userId: userId ?? this.userId,
        title: title ?? this.title,
        description: description ?? this.description,
        emoji: emoji ?? this.emoji,
        frequency: frequency ?? this.frequency,
        customDays: customDays ?? this.customDays,
        isShared: isShared ?? this.isShared,
        targetUnit: targetUnit ?? this.targetUnit,
        targetValue: targetValue ?? this.targetValue,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'userId': userId,
        'title': title,
        if (description != null) 'description': description,
        'emoji': emoji,
        'frequency': frequency,
        'customDays': customDays,
        'isShared': isShared,
        if (targetUnit != null) 'targetUnit': targetUnit,
        if (targetValue != null) 'targetValue': targetValue,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DailyHabit.fromJson(Map<String, dynamic> json) => DailyHabit(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        userId: json['userId'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        emoji: json['emoji'] as String? ?? '✅',
        frequency: json['frequency'] as String? ?? 'daily',
        customDays: (json['customDays'] as List? ?? []).cast<int>(),
        isShared: json['isShared'] as bool? ?? false,
        targetUnit: json['targetUnit'] as String?,
        targetValue: json['targetValue'] as int?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class DailyHabitCompletion {
  final String id;
  final String habitId;
  final String userId;
  final DateTime date;
  final int? value; // actual value logged (vs targetValue)
  final String? note;
  final DateTime createdAt;

  const DailyHabitCompletion({
    required this.id,
    required this.habitId,
    required this.userId,
    required this.date,
    this.value,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'habitId': habitId,
        'userId': userId,
        'date': date.toIso8601String().substring(0, 10),
        if (value != null) 'value': value,
        if (note != null) 'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DailyHabitCompletion.fromJson(Map<String, dynamic> json) => DailyHabitCompletion(
        id: json['id'] as String,
        habitId: json['habitId'] as String,
        userId: json['userId'] as String,
        date: DateTime.parse(json['date'] as String),
        value: json['value'] as int?,
        note: json['note'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ─────────────────────────────────────────────
// ReadingPlan
// ─────────────────────────────────────────────

class ReadingPlanEntry {
  final int day;
  final String title;
  final String? scripture;
  final String? content;
  final bool completed;

  const ReadingPlanEntry({
    required this.day,
    required this.title,
    this.scripture,
    this.content,
    this.completed = false,
  });

  ReadingPlanEntry copyWith({int? day, String? title, String? scripture, String? content, bool? completed}) =>
      ReadingPlanEntry(
        day: day ?? this.day,
        title: title ?? this.title,
        scripture: scripture ?? this.scripture,
        content: content ?? this.content,
        completed: completed ?? this.completed,
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        'title': title,
        if (scripture != null) 'scripture': scripture,
        if (content != null) 'content': content,
        'completed': completed,
      };

  factory ReadingPlanEntry.fromJson(Map<String, dynamic> json) => ReadingPlanEntry(
        day: json['day'] as int,
        title: json['title'] as String,
        scripture: json['scripture'] as String?,
        content: json['content'] as String?,
        completed: json['completed'] as bool? ?? false,
      );
}

class ReadingPlan {
  final String id;
  final String familyId;
  final String title;
  final String? description;
  final List<ReadingPlanEntry> entries;
  final DateTime? startDate;
  final String createdBy;
  final DateTime createdAt;

  const ReadingPlan({
    required this.id,
    required this.familyId,
    required this.title,
    this.description,
    this.entries = const [],
    this.startDate,
    required this.createdBy,
    required this.createdAt,
  });

  int get completedCount => entries.where((e) => e.completed).length;
  double get progress => entries.isEmpty ? 0 : completedCount / entries.length;

  ReadingPlan copyWith({
    String? id,
    String? familyId,
    String? title,
    String? description,
    List<ReadingPlanEntry>? entries,
    DateTime? startDate,
    String? createdBy,
    DateTime? createdAt,
  }) =>
      ReadingPlan(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        title: title ?? this.title,
        description: description ?? this.description,
        entries: entries ?? this.entries,
        startDate: startDate ?? this.startDate,
        createdBy: createdBy ?? this.createdBy,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'title': title,
        if (description != null) 'description': description,
        'entries': entries.map((e) => e.toJson()).toList(),
        if (startDate != null) 'startDate': startDate!.toIso8601String(),
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ReadingPlan.fromJson(Map<String, dynamic> json) => ReadingPlan(
        id: json['id'] as String,
        familyId: json['familyId'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        entries: (json['entries'] as List? ?? [])
            .map((e) => ReadingPlanEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        startDate: json['startDate'] != null ? DateTime.parse(json['startDate'] as String) : null,
        createdBy: json['createdBy'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
