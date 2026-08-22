import React from 'react'
import { t } from '../i18n.js'
import { Box, Text } from '../ui.js'
import { Pane } from './design-system/Pane.js'
import { Select } from './Select.js'
import { HintLine } from './design-system/HintLine.js'

/**
 * Bare `/workspace` action menu: the built-in subcommands (resume / rename /
 * open) plus any dynamically registered workspace extensions. Enter runs the
 * focused action through the same paths a hand-typed subcommand takes;
 * actions needing free text (rename/open) fall back to their usage notice.
 */
export function WorkspaceMenuPicker({
  options,
  focusIndex,
}: {
  options: readonly { id: string; label: string; description: string }[]
  focusIndex: number
}): React.ReactNode {
  return (
    <Pane color="permission">
      <Box flexDirection="column">
        <Box marginBottom={1}>
          <Text color="remember" bold>
            {t('workspace-menu-title')}
          </Text>
        </Box>
        <Select
          options={options.map(option => ({
            value: option.id,
            label: option.label,
            description: option.description,
          }))}
          focusIndex={focusIndex}
          selectedValue={undefined}
        />
        <Text dimColor italic>
          <HintLine text={t('hint-confirm-exit')} />
        </Text>
      </Box>
    </Pane>
  )
}
