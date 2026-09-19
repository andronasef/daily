import {defineField, defineType} from 'sanity'

/// The "big thing" you intercede for: a person, a situation, anything.
/// Prayers (intercedePrayer) reference it.
export const intercedeEntity = defineType({
  name: 'intercedeEntity',
  title: 'Intercede — Entity',
  type: 'document',
  fields: [
    defineField({name: 'name', type: 'string', validation: (r) => r.required()}),
    defineField({name: 'note', type: 'text', rows: 3}),
    defineField({name: 'createdAt', type: 'datetime'}),
  ],
  preview: {select: {title: 'name', subtitle: 'note'}},
})
