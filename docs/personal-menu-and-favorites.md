# القائمة الشخصية والمفضلات

أُزيلت مجموعات «أدواتي» و«الحساب» وخياراتها من القائمة الجانبية. بقي الملف الشخصي في رأس القائمة، ثم اشتراكي، مشاركة جدولي الخاص، جدولي الدراسي، والمفضلات. الإعدادات في الأسفل.

- الملف الشخصي والجدول الدراسي يستخدمان واجهاتهما الحالية.
- اشتراكي يعرض الوصول المتاح حاليًا؛ لم يُضف نظام دفع أو تُخمن حالة اشتراك مدفوع.
- المشاركة تنشئ نسخة نصية من الجدول الحالي. يختار المستخدم الأيام والمهام المنجزة وإظهار الاسم والملاحظات. الاسم والملاحظات غير محددين افتراضيًا. المشاركة تبدأ فقط عند ضغط المستخدم، عبر Web Share، أو النسخ، أو تنزيل TXT؛ لا يوجد رابط عام للجدول.
- المفضلات محفوظة في الحساب، وتظهر على الأجهزة الأخرى عند تحميلها. يمكن إضافة وإزالة أي مادة من زر الحفظ في بطاقتها، والبحث والترتيب داخل صفحة المفضلات. فشل الشبكة لا يُغيّر حالة الحفظ محليًا.
- الإعدادات تتيح الوضع الفاتح/الداكن، حجم خط القراءة، تقليل الحركة، الملف الشخصي وتسجيل الخروج. تفضيلات العرض محفوظة على الجهاز.
- ميزات المحاضرات والفيديوهات والأسئلة والبطاقات تبقى متاحة من الرئيسية؛ تغيرت عناصر القائمة الجانبية فقط.

## تعديل قاعدة البيانات

طُبق SQL التالي مرة واحدة على المشروع `wuvzteosknrzddsaexez` لإنشاء جدول جديد دون تعديل أو حذف البيانات السابقة. الجدول ليس متاحًا لـ anon، ولا يمتلك المستخدمون صلاحية UPDATE. سياسات SELECT/INSERT/DELETE تقصر الوصول على صاحب السجل.

```sql
create table public.lecture_favorites (
 user_id uuid not null references auth.users(id) on delete cascade,
 lecture_id uuid not null references public.lectures(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key (user_id,lecture_id)
);
create index lecture_favorites_lecture_id_idx on public.lecture_favorites(lecture_id);
alter table public.lecture_favorites enable row level security;
revoke all on public.lecture_favorites from public, anon, authenticated;
grant select, insert, delete on public.lecture_favorites to authenticated;
create policy favorites_read_own on public.lecture_favorites for select to authenticated using ((select auth.uid())=user_id);
create policy favorites_insert_own on public.lecture_favorites for insert to authenticated with check ((select auth.uid())=user_id);
create policy favorites_delete_own on public.lecture_favorites for delete to authenticated using ((select auth.uid())=user_id);

```

## التحقق

- اختبار SQL داخل معاملة أُلغيت: حفظ وقراءة وحذف المفضلة الخاصة بالحساب تنجح؛ قراءة وحذف مفضلات حساب آخر ممنوعة، والإدراج باسمه مرفوض.
- فحوص المتصفح ببيانات محاكاة في الوضعين وعلى عروض 390/768/1440: عناصر القائمة، الملف الشخصي، جميع الصفحات، معاينة الجدول والمشاركة والنسخ، الخيارات الخاصة، المفضلات وحفظها وإزالتها وفشل الشبكة، البحث وفتح القارئ، المظهر والخط وتقليل الحركة.
- لا يوجد اختبار دخول تفاعلي بحساب المستخدم؛ صلاحيات قاعدة البيانات فُحصت مباشرة.
- Security Advisors لم يبلغ عن مشكلة في الجدول الجديد. إعدادات Auth ودوال الأدوار الموجودة لم تُغير في هذا العمل.

## تجربة التغيير

افتح القائمة، ثم المفضلات. اضغط «استعراض المحاضرات» واحفظ مادة بعلامة الحفظ، ثم ارجع للمفضلات. لمشاركة الجدول، أضف مهامًا في «جدولي الدراسي»، ثم افتح «مشاركة جدولي الخاص» وراجع المعاينة قبل اختيار المشاركة أو النسخ.
