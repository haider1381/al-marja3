# استيراد بيانات Claude — 2026-10-02

المشروع: `wuvzteosknrzddsaexez`. التصدير: «المرجع v1.0»، تاريخ التصدير `2026-10-02T22:59:04.766Z`، من JSON المنسوخ في المحادثة.

## النتيجة

- 29 سجلًا في التصدير: 27 نصًا ورابطا Google Drive.
- قبل الاستيراد: مادتان (Multiple sclerosis وHeart failure).
- أُضيفت 28 مادة. رُبط Heart failure بالسجل الموجود بعد مقارنة النص والحقول؛ لم يُستبدل أو يُحذف أي سجل سابق.
- بعد الاستيراد: 30 مادة.
- أُبقيت العناوين والمصادر والتخصصات والمواضيع والأنواع والملاحظات والروابط والنصوص دون تلخيص.
- حُولت تواريخ Unix بالميلي ثانية إلى timestamptz. تاريخ Heart failure الحالي بقي كما هو؛ التاريخ الأصلي محفوظ في original_record.createdAt.
- المعرّفات القديمة ليست UUID. الخريطة بين كل legacy_id وlecture_id محفوظة في private.claude_lecture_import مع السجل الأصلي وتصنيف inserted أو matched_existing.
- لا يتضمن التصدير أسئلة منظمة أو تفسيرات أسئلة مستقلة؛ لم تُخمن أو تُولد أسئلة.
- لا تحتاج البيانات إلى تعديل index.html أو نشر واجهة جديدة.

## الملفات

نُزّل ملفا PDF من Google Drive دون الحاجة إلى جلسة Claude، وحُفظا في مخزن lecture-files الخاص. بقيت الروابط الأصلية محفوظة أيضًا:

| المادة | file_path | الحجم | SHA-256 |
| --- | --- | ---: | --- |
| Headache | pdf/claude-import/mz6mteigfedarzzkldaa.pdf | 3,077,208 | eb884c9561946fcf1cf3041e2a64cfca362a42c683470c2b1c180f47e90d7dfe |
| Stroke | pdf/claude-import/ysi38jfs40chjcjycmxi.pdf | 9,209,165 | 88960333d330aa6e3fd5aa850f2d2b27f9d6cf7ec03ed43607ac62f6fbc5a11b |

لم توجد مرفقات أخرى في هذا التصدير أو روابط تعتمد على Claude. لم يُفقد أي من الملفين المتاحين. لم تُغير أسماء الأنواع الأصلية حتى عند وجود PDF.

## النسخة الاحتياطية والمخطط

أُخذت نسخة من السجلين كاملين قبل إدراج المواد في setup_backup.lectures_before_claude_20261002. سجل الاستيراد والنسخة الاحتياطية غير متاحين لـ anon أو authenticated. RLS مفعّل، ولا توجد سياسات تمنح مستخدمي الموقع الوصول إليهما، وهذا مقصود. لم يتغير مخطط public.lectures أو سياسات الموقع أو صلاحيات المحررين.

التعديل الإضافي الذي طُبق:

```sql
-- Additive, private import bookkeeping. Public lecture schema and policies are unchanged.
create table if not exists setup_backup.lectures_before_claude_20261002 as table public.lectures;
alter table setup_backup.lectures_before_claude_20261002 enable row level security;
revoke all on setup_backup.lectures_before_claude_20261002 from public, anon, authenticated;
create table if not exists private.claude_lecture_import (
 legacy_id text primary key,
 lecture_id uuid not null references public.lectures(id),
 original_record jsonb not null,
 imported_at timestamptz not null default now(),
 disposition text not null check (disposition in ('inserted','matched_existing'))
);
alter table private.claude_lecture_import enable row level security;
revoke all on private.claude_lecture_import from public, anon, authenticated;

```

## إعادة التشغيل

[مولّد SQL](../scripts/prepare_claude_import.py) يتحقق من عدد السجلات والحقول وأنواعها، ثم ينتج استيرادًا بمعاملة واحدة:

```sh
python scripts/prepare_claude_import.py /private/export.json > /private/import.sql
```

راجع SQL ونفّذه باتصال إداري بعد تطبيق المخطط أعلاه. لا تُودع ملفات البيانات أو النسخ الاحتياطية أو المفاتيح في المستودع العام.

يفحص legacy_id والسجل الأصلي قبل الكتابة. إعادة نفس التصدير لا تُضيف نسخًا. عند تغير بيانات معرّف قديم أو وجود أكثر من تطابق كامل يتوقف الاستيراد ويُلغي المعاملة. تشابه العنوان وحده لا يُستخدم لاكتشاف التكرار. لا يتضمن الاستيراد UPDATE أو DELETE على المواد الموجودة؛ ربط PDF الجديد جرى لاحقًا فقط عندما كان file_path فارغًا، مع فحص التعارض.

لا يقوم مولّد SQL برفع الملفات؛ مسارات الملفات المرفوعة محفوظة بالفعل في الموقع.

## نقل PDF المؤقت

استُخدمت Edge Function مؤقتة للنقل فقط، محمية برمز عشوائي 256 بت محدود الصلاحية. قبلت الملفين المعروفين فقط بعد التحقق من الحجم وSHA-256، ورفضت استبدال ملف مختلف. مفاتيح Supabase بقيت على الخادم. بعد النقل والتحقق أُعيد نشر الدالة بوضع verify_jwt=true وجسم يعيد 410 دائمًا؛ أُزيل رمز النقل. المخزن بقي public=false، ولم تُفتح أي سياسات عامة.

## التحقق

- رُبطت السجلات الـ29، وطابقت جميع حقول المحتوى ملف JSON المُجهز للاستيراد.
- اختلافات تواريخ المواد الجديدة: صفر.
- التغييرات في السجلين السابقين مقارنة بالنسخة الاحتياطية: صفر.
- إعادة تشغيل الاستيراد: الإجمالي بقي 30 سجلًا.
- حجم وبصمة كل PDF مطابقان بعد قراءة الملف من المخزن الخاص.
- اختبار سياسات القراءة بمعاملة SQL تحت دور authenticated مع هوية اختبار: 30 مادة وملفا PDF مستوردان قابلان للقراءة.
- اختبار واجهة المتصفح بالبيانات الفعلية المسترجعة من قاعدة البيانات، مع محاكاة جلسة الواجهة: 30 بطاقة، 27 قارئ نص، 3 أزرار PDF (بينها الملف السابق)، رابطان خارجيان، ونجاح البحث؛ على عروض 390 و768 و1440 بكسل.
- لم يُجر اختبار دخول تفاعلي بحساب المستخدم؛ يمكن تأكيده بالخطوات أدناه.
- فحص Security Advisors أظهر إشعارات الجداول الخاصة بلا سياسات (مقصودة لمنع الوصول)، وتحذيرات إعدادات Auth ودوال الأدوار الموجودة. لم تُغير هذه الإعدادات ضمن الاستيراد. مرجع [الجداول المحمية بلا سياسات](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) و[دوال الأدوار](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

## التحقق في الموقع

افتح https://haider1381.github.io/al-marja3/ وسجل الدخول، ثم افتح المحاضرات/المكتبة وأزل الفلاتر. ابحث عن Asthma أو Congenital Heart Diseases وافتح النص. ابحث عن Headache وStroke واضغط زر PDF. اختر المصدر «محاضرات جونيور» لإظهار الملخصات القديمة؛ ابحث عن Medicine ثم Cardiology أو Respiratory للمواضيع المستوردة.

حفظت النسخة الأصلية المُجهزة وخريطة المعرّفات والنسخ الاحتياطية محليًا أثناء العمل، ولم أنشرها في المستودع العام.
