import {defineField, defineType} from 'sanity'

export const verse = defineType({
  name: 'verse',
  title: 'Verse',
  type: 'document',
  fields: [
    defineField({name: 'title', type: 'string'}),
    defineField({name: 'verse', type: 'text'}),
    defineField({name: 'language', type: 'string'}),
  ],
})
