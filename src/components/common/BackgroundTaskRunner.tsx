import { useEffect, useRef, useCallback } from 'react';
import { useConfigStore } from '../../stores/useConfigStore';
import { useAccountStore } from '../../stores/useAccountStore';

// ============================================================================
// Smart Scheduled Refresh Strategy
// - Critical time points: 07:00, 11:00, 16:00, 21:00
// - Within +/-5 minutes of each point: refresh every 1 minute (dense mode)
// - 07:00-21:00 outside windows: no refresh (blocked mode)
// - 21:00-07:00: normal interval refresh
// ============================================================================

const CRITICAL_TIMES = [
    { hour: 7, minute: 0 },
    { hour: 11, minute: 0 },
    { hour: 16, minute: 0 },
    { hour: 21, minute: 0 },
];
const WINDOW_MINUTES = 5;

type RefreshMode = 'dense' | 'blocked' | 'normal';

function getRefreshMode(now: Date): RefreshMode {
    const h = now.getHours();
    const m = now.getMinutes();
    const totalMinutes = h * 60 + m;

    // Check if within any critical window (+/- 5 minutes)
    for (const t of CRITICAL_TIMES) {
        const target = t.hour * 60 + t.minute;
        if (Math.abs(totalMinutes - target) <= WINDOW_MINUTES) {
            return 'dense';
        }
    }

    // 07:00-21:00 outside windows -> blocked
    if (h >= 7 && h < 21) {
        return 'blocked';
    }

    // 21:00-07:00 -> normal interval
    return 'normal';
}

function BackgroundTaskRunner() {
    const { config } = useConfigStore();
    const { refreshAllQuotas } = useAccountStore();

    // Use refs to track previous state to detect "off -> on" transitions
    const prevAutoRefreshRef = useRef(false);
    const prevAutoSyncRef = useRef(false);

    // Track last normal refresh time for interval-based refresh in normal mode
    const lastNormalRefreshRef = useRef<number>(0);

    // Smart refresh tick handler (called every 60 seconds)
    const smartRefreshTick = useCallback(() => {
        if (!config) return;
        const { refresh_interval } = config;
        const now = new Date();
        const mode = getRefreshMode(now);

        if (mode === 'dense') {
            console.log(`[BackgroundTask] Smart refresh: DENSE mode (${now.toLocaleTimeString()}) - refreshing`);
            refreshAllQuotas();
            lastNormalRefreshRef.current = Date.now();
        } else if (mode === 'blocked') {
            // Do nothing - refresh is blocked during 07:00-21:00 outside critical windows
        } else {
            // Normal mode (22:00-08:00): respect refresh_interval
            const elapsed = (Date.now() - lastNormalRefreshRef.current) / 1000 / 60;
            if (elapsed >= refresh_interval) {
                console.log(`[BackgroundTask] Smart refresh: NORMAL mode (${now.toLocaleTimeString()}) - refreshing (interval: ${refresh_interval}min)`);
                refreshAllQuotas();
                lastNormalRefreshRef.current = Date.now();
            }
        }
    }, [config, refreshAllQuotas]);

    // Auto Refresh Quota Effect - Smart Scheduled Strategy
    useEffect(() => {
        if (!config) return;

        let intervalId: ReturnType<typeof setTimeout> | null = null;
        const { auto_refresh } = config;

        // Check if we just turned it on
        if (auto_refresh && !prevAutoRefreshRef.current) {
            console.log('[BackgroundTask] Auto-refresh enabled, executing immediately...');
            refreshAllQuotas();
            lastNormalRefreshRef.current = Date.now();
        }
        prevAutoRefreshRef.current = auto_refresh;

        if (auto_refresh) {
            console.log('[BackgroundTask] Starting smart scheduled refresh (tick every 60s)');
            // Tick every 60 seconds to check time-based refresh strategy
            intervalId = setInterval(() => {
                smartRefreshTick();
            }, 60 * 1000);
        }

        return () => {
            if (intervalId) {
                console.log('[BackgroundTask] Clearing smart refresh timer');
                clearInterval(intervalId);
            }
        };
    }, [config?.auto_refresh, config?.refresh_interval, smartRefreshTick]);

    // Auto Sync Current Account Effect
    useEffect(() => {
        if (!config) return;

        let intervalId: ReturnType<typeof setTimeout> | null = null;
        const { auto_sync, sync_interval } = config;
        const { syncAccountFromDb } = useAccountStore.getState();

        // Check if we just turned it on
        if (auto_sync && !prevAutoSyncRef.current) {
            console.log('[BackgroundTask] Auto-sync enabled, executing immediately...');
            syncAccountFromDb();
        }
        prevAutoSyncRef.current = auto_sync;

        if (auto_sync && sync_interval > 0) {
            console.log(`[BackgroundTask] Starting auto-sync account timer: ${sync_interval} seconds`);
            intervalId = setInterval(() => {
                console.log('[BackgroundTask] Auto-syncing current account from DB...');
                syncAccountFromDb();
            }, sync_interval * 1000);
        }

        return () => {
            if (intervalId) {
                console.log('[BackgroundTask] Clearing auto-sync timer');
                clearInterval(intervalId);
            }
        };
    }, [config?.auto_sync, config?.sync_interval]);

    // Render nothing
    return null;
}

export default BackgroundTaskRunner;
