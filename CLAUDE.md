# ZeroTab — Claude Code Context

ZeroTab is an AI-powered personal-finance app for India (Flutter + Supabase + Riverpod + go_router).
The Flutter app lives in `zerotab-app/`; the backend in `zerotab-backend/`.

## Design System — READ BEFORE TOUCHING ANY UI

The app has ONE premium design system in `zerotab-app/lib/core/theme/app_theme.dart`
(purple-warm near-black dark theme, DM Sans / DM Mono). It is the single source of truth.
The #1 cause of past "looks unfinished" UI was screens inventing their own near-duplicate
colours. Do not reintroduce that.

**Hard rules:**

1. **Colours come from `AppColors` — never raw hex in feature/shared code.** Banned drift values
   (auto-checked): `7B2FFE`, `22C55E`, `EF4444`, `F59E0B`, `FF8C42`, `00CFDE`, `00C896`, `00C9B1`,
   `3B82F6`, `FFAA00`. Use `AppColors.accent / green / red / gold / teal / dataETF` etc.
   Run `pwsh zerotab-app/tool/check_theme.ps1` — it fails if any reappear.
2. **Colour semantics are strict:** green = positive only, red = negative only,
   gold = warning/debt/achievement, **teal = AI only**, **accent (purple) = brand & interactive only**.
   Never mix brand accent with P&L colours in one cluster.
3. **No emoji as icons.** Use `ZtIcons` (`lib/core/icons/zt_icons.dart`) — `ZtIcons.category(...)`,
   `ZtIcons.groupType(...)` — or a Material `*_outlined` icon. Emoji in comments/copy is fine.
4. **Money uses tabular figures.** Render amounts with `ZtAmount` / `AnimatedZtAmount`
   (`lib/shared/widgets/zt_amount.dart`) or `context.money()` — never a plain DM Sans `Text` for a
   number. `formatInr()` (`lib/core/utils/formatters.dart`) handles ₹ lakh/crore formatting.
5. **Compose with the kit, don't hand-roll.** Shared widgets in `lib/shared/widgets/`:
   `ZtCard`, `ZtSection`/`ZtSectionHeader`/`ZtScreenHeader`, `ZtListRow`/`ZtIconBadge`,
   `ZtButton`/`ZtChip`/`ZtSegmented`, `showZtSheet`/`showZtDialog`/`ZtSwitch`/`showZtToast`,
   `ZtEmptyState`, `ZtGlass`, `ZtAvatar`, `ZtShimmerBox` (animated), and chart helpers in
   `zt_chart.dart` (`ZtDonut`, `ZtAreaChart`, `ZtChartCaption`). Motion/haptics tokens live in
   `lib/core/theme/app_motion.dart` (`AppMotion`, `Haptics`).

## Verify

```powershell
cd zerotab-app
dart analyze lib            # must be 0 errors
pwsh tool/check_theme.ps1   # must pass (no drift colours)
flutter build apk --debug   # must compile
```
