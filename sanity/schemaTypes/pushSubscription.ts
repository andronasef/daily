import {defineField, defineType} from 'sanity'

export const pushSubscription = defineType({
  name: 'pushSubscription',
  title: 'Push Subscription',
  type: 'document',
  readOnly: true,
  fields: [
    defineField({name: 'blob', type: 'text'}),
    defineField({name: 'tzOffset', type: 'number'}),
  ],
})
