import { ref, readonly, onMounted, onUnmounted } from "vue";

export function useOnlineStatus(initialManual: boolean | null = null) {
  const auto = ref(navigator.onLine);
  const manual = ref<boolean | null>(initialManual);
  const isOnline = ref(manual.value ?? auto.value);

  const update = () => (isOnline.value = manual.value ?? auto.value);

  const handler = () => {
    auto.value = navigator.onLine;
    update();
  };

  const set = (value: boolean | null) => {
    manual.value = value;
    update();
  };

  onMounted(() => {
    window.addEventListener("online", handler);
    window.addEventListener("offline", handler);
  });

  onUnmounted(() => {
    window.removeEventListener("online", handler);
    window.removeEventListener("offline", handler);
  });

  return {
    isOnline: readonly(isOnline),
    setOnline: () => set(true),
    setOffline: () => set(false),
    setAuto: () => set(null),
  };
}
