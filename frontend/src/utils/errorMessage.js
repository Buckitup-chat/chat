export default function errorMessage(error) {
	// web3 reason string
	try {
		let str1 = error.message;
		const toSearch1 = `reverted with reason string '`;
		const toSearch2 = `'`;
		const index1 = str1.indexOf(toSearch1);
		if (index1 != -1) {
			str1 = str1.slice(index1 + toSearch1.length);
			const index2 = str1.indexOf(toSearch2);
			if (index2 != -1) {
				return str1.slice(0, index2);
			}
		}
	} catch (error) {
		//console.log('ParseErrorMessage web3 reason string', error)
	}

	// web3 ethjs-query
	try {
		let str1 = error.message;
		const toMatch = '[ethjs-query] while formatting outputs from RPC';
		const toSearch1 = `"message":"`;
		const toSearch2 = `"`;

		const indexMatch = str1.indexOf(toMatch);
		const index1 = str1.indexOf(toSearch1);
		if (indexMatch != -1 && index1 != -1) {
			str1 = str1.slice(index1 + toSearch1.length);
			const index2 = str1.indexOf(toSearch2);
			if (index2 != -1) {
				return 'RPC: ' + str1.slice(0, index2);
			}
		}
	} catch (error) {
		//console.log('ParseErrorMessage web3 ethjs query', error)
	}

	// match
	let errStr;
	try {
		if (error.response?.data?.message) {
			errStr = error.response.data.message.toString();
		} else if (error?.message) {
			errStr = error.message.toString();
		} else {
			errStr = error.toString();
		}

		const match = errStr.match(/reason="(.*?)"/i);
		if (match) {
			errStr = match[1];
		} else if (errStr.includes('code=')) {
			errStr = errStr.replace(/ *\([^)]*\) */g, '');
		}
	} catch (error) {
		//console.log('ParseErrorMessage match', error)
	}

	return errStr.length <= 300 ? errStr : errStr.slice(0, 300) + '...';
}
