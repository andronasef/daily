import {defineField, defineType} from 'sanity'

export const memorizeVerse = defineType({
  name: 'memorizeVerse',
  title: 'آية للحفظ (Memorize Verse)',
  type: 'document',
  fields: [
    defineField({
      name: 'title',
      title: 'الشاهد (Reference)',
      description: 'مثال: مزمور 119: 11 أو يوحنا 3: 16',
      type: 'string',
      validation: (rule) => rule.required(),
    }),
    defineField({
      name: 'verse',
      title: 'نص الآية',
      type: 'text',
      rows: 3,
      validation: (rule) => rule.required(),
    }),
    defineField({
      name: 'category',
      title: 'التصنيف / الحزمة (Pack)',
      description: 'مثال: طمأنينة وسلام، الحرب الروحية، الإيمان والرجاء، مواعيد الله',
      type: 'string',
    }),
    defineField({
      name: 'categoryRef',
      title: 'ربط بحزمة مصنفة',
      type: 'reference',
      to: [{type: 'verseCategory'}],
    }),
    defineField({
      name: 'translation',
      title: 'الترجمة الكتابية',
      description: 'مثال: فاندايك (Van Dyck)، المشتركة، المبسطة',
      type: 'string',
      initialValue: 'فاندايك',
    }),
    defineField({
      name: 'audioFile',
      title: 'ملف صوتي مرجعي (اختياري)',
      description: 'تسجيل تلاوة صوتية للآية يمكن الاستماع إليها في التطبيق',
      type: 'file',
      options: {
        accept: 'audio/*',
      },
    }),
    defineField({
      name: 'voiceRecordings',
      title: 'تسجيلات صوتية وفويسات (Voice Notes)',
      type: 'array',
      of: [
        {
          type: 'object',
          fields: [
            {name: 'title', type: 'string', title: 'عنوان التسجيل'},
            {name: 'audioFile', type: 'file', title: 'الملف الصوتي', options: {accept: 'audio/*'}},
            {name: 'recordedAt', type: 'datetime', title: 'تاريخ التسجيل'},
          ],
        },
      ],
    }),
    defineField({
      name: 'order',
      title: 'ترتيب العرض',
      type: 'number',
    }),
  ],
  preview: {
    select: {
      title: 'title',
      subtitle: 'verse',
      category: 'category',
    },
    prepare({title, subtitle, category}) {
      return {
        title: title || 'بدون شاهد',
        subtitle: category ? `[${category}] ${subtitle || ''}` : subtitle || '',
      }
    },
  },
})
