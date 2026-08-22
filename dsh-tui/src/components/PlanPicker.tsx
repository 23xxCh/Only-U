import React from 'react'
import { t } from '../i18n.js'
import { Box, Text } from '../ui.js'
import { Pane } from './design-system/Pane.js'
import { Select } from './Select.js'
import { HintLine } from './design-system/HintLine.js'

/**
 * `/plan` on/off picker. The command itself is registered by dsh-plan-mode
 * on the harness side; bare `/plan` opens this picker (with the current
 * state marked) and Enter dispatches `/plan` or `/plan off` through the
 * same external-command path a hand-typed argument takes.
 */
export function PlanPicker({
  focusIndex,
  currentOn,
}: {
  focusIndex: number
  currentOn: boolean
}): React.ReactNode {
  return (
    <Pane color="permission">
      <Box flexDirection="column">
        <Box marginBottom={1}>
          <Text color="remember" bold>
            {t('plan-picker-title')}
          </Text>
        </Box>
        <Select
          options={[
            { value: 'on', label: t('plan-mode-on'), description: t('plan-mode-on-desc') },
            { value: 'off', label: t('plan-mode-off'), description: t('plan-mode-off-desc') },
          ]}
          focusIndex={focusIndex}
          selectedValue={currentOn ? 'on' : 'off'}
        />
        <Text dimColor italic>
          <HintLine text={t('hint-confirm-exit')} />
        </Text>
      </Box>
    </Pane>
  )
}
