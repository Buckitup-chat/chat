import $swal from '@/libs/swal';

export default async function (text, notify = true) {
	if (!text) return;
	let success;

	if (!navigator.clipboard) {
		var textArea = document.createElement('textarea');
		textArea.value = text;
		// Avoid scrolling to bottom
		textArea.style.top = '0';
		textArea.style.left = '0';
		textArea.style.position = 'fixed';
		document.body.appendChild(textArea);
		textArea.focus();
		textArea.select();
		try {
			success = document.execCommand('copy');
		} catch (err) {
			console.error('copy to clipboard error 1', err);
		}
		document.body.removeChild(textArea);
		return true;
	} else {
		try {
			await navigator.clipboard.writeText(text);
			success = true;
		} catch (error) {
			console.error('copy to clipboard error 2', err);
		}
	}

	if (notify) {
		if (success) {
			$swal.fire({
				icon: 'success',
				text: 'Copied to clipboard',
				timer: 1500,
			});
		} else {
			$swal.fire({
				icon: 'error',
				text: 'Error copying to clipboard. Please do it manually',
				timer: 3000,
			});
		}
	}
	return success;
}
