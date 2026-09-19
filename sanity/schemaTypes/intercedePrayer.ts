import {defineArrayMember, defineField, defineType} from 'sanity'

/// One prayer under an entity. `completedAt` null = still praying.
/// `logs` holds every "صليت" tap — kept inline (not its own document type)
/// because a log only means anything next to its prayer.
export const intercedePrayer = defineType({
  name: 'intercedePrayer',
  title: 'Intercede — Prayer',
  type: 'document',
  fields: [
    defineField({name: 'title', type: 'string', validation: (r) => r.required()}),
    defineField({
      name: 'entity',
      type: 'reference',
      to: [{type: 'intercedeEntity'}],
      validation: (r) => r.required(),
    }),
    defineField({name: 'startedAt', type: 'datetime'}),
    defineField({
      name: 'completedAt',
      type: 'datetime',
      description: 'Set = completed, moves to the archive.',
    }),
    defineField({
      name: 'outcome',
      title: 'Outcome',
      type: 'text',
      rows: 3,
      description: 'What happened / how it was answered.',
    }),
    defineField({
      name: 'logs',
      type: 'array',
      of: [
        defineArrayMember({
          type: 'object',
          name: 'prayerLog',
          fields: [
            defineField({name: 'prayedAt', type: 'datetime'}),
            defineField({name: 'note', type: 'text', rows: 2}),
          ],
          preview: {select: {title: 'prayedAt', subtitle: 'note'}},
        }),
      ],
    }),
  ],
  preview: {select: {title: 'title', subtitle: 'entity.name'}},
})
