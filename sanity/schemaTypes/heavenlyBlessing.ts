import {defineField, defineType} from 'sanity'

export const heavenlyBlessing = defineType({
  name: 'heavenlyBlessing',
  title: 'Heavenly Blessing',
  type: 'document',
  fields: [
    defineField({name: 'name', type: 'string'}),
    defineField({name: 'mean', type: 'text'}),
    defineField({name: 'content', type: 'text'}),
    defineField({name: 'order', type: 'number'}),
    defineField({name: 'notionId', type: 'string', readOnly: true}),
  ],
  orderings: [{title: 'Order', name: 'order', by: [{field: 'order', direction: 'asc'}]}],
})
