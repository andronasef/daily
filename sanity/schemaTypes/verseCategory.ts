import {defineField, defineType} from 'sanity'

export const verseCategory = defineType({
  name: 'verseCategory',
  title: 'حزمة / تصنيف الآيات (Verse Pack)',
  type: 'document',
  fields: [
    defineField({
      name: 'name',
      title: 'اسم الحزمة / الموضوع',
      type: 'string',
      validation: (rule) => rule.required(),
    }),
    defineField({
      name: 'slug',
      title: 'المعرّف الإنجليزي (Slug)',
      type: 'slug',
      options: {source: 'name'},
    }),
    defineField({
      name: 'description',
      title: 'وصف الحزمة',
      type: 'text',
      rows: 2,
    }),
    defineField({
      name: 'icon',
      title: 'رمز الأيقونة (مثل spa, shield, favorite)',
      type: 'string',
    }),
    defineField({
      name: 'order',
      title: 'ترتيب العرض',
      type: 'number',
    }),
  ],
})
