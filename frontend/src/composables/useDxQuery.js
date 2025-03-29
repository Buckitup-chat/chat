import { ref, watchEffect, onUnmounted, computed } from 'vue';
import { isSpace } from '@dxos/client/echo';

export function useDxQuery(spaceOrEcho, filter, options, params = {}, deps = []) {
	const objects = ref([]);

	let unsubscribe = () => {}; // Cleanup function

	const updateQuery = async () => {
		if (!spaceOrEcho) {
			objects.value = [];
			return;
		}

		// Create query
		const query = isSpace(spaceOrEcho) ? spaceOrEcho.db.query(filter, options) : spaceOrEcho?.query(filter, options);

		if (!query) {
			objects.value = [];
			return;
		}

		// Subscribe to changes
		unsubscribe = query.subscribe(() => {
			objects.value = query.objects || [];
		});

		// Initial fetch
		objects.value = (await query.run()) || [];
	};

	// React to spaceOrEcho, filter, and dependencies
	watchEffect(() => {
		updateQuery();
	});

	// Cleanup on unmount
	onUnmounted(() => {
		unsubscribe();
	});

	// ✅ Return only the first object if `params.single` is true
	const result = computed(() => (params.single ? objects.value[0] || null : objects.value));

	return result;
}
