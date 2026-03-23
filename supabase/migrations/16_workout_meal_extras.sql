-- Exercise how-to fields + meal plan prep/servings

alter table workout_exercises add column if not exists technique_notes text;
alter table workout_exercises add column if not exists reference_url text;

alter table meal_plans add column if not exists servings integer;
alter table meal_plans add column if not exists prep_notes text;
alter table meal_plans add column if not exists notes text;
