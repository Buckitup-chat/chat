import { BigNumber, utils } from 'ethers';
import dayjs from 'dayjs';

export default {
	addressShort(tokenAddress) {
		if (tokenAddress) return tokenAddress.replace(tokenAddress.substring(6, 38), '...');
		return '...';
	},

	txHashShort(txHash) {
		if (txHash) return txHash.replace(txHash.substring(8, 60), '.....');
		return '.....';
	},

	//formatWalletBalance(val) {
	//  if (!val) return '--'
	//  return this.numberWithCommas(BigNumber.from(val).toString());
	//},

	formatTimestamp(val) {
		if (!val) return '--';
		return dayjs(parseInt(val) * 1000).format('YYYY-MM-DD HH:mm:ss');
	},

	secondsToHMS(value) {
		//const sec = parseInt(value, 10); // convert value to number if it's string
		//let hours   = Math.floor(sec / 3600); // get hours
		//let minutes = Math.floor((sec - (hours * 3600)) / 60); // get minutes
		//let seconds = sec - (hours * 3600) - (minutes * 60); //  get seconds
		//// add 0 if value < 10; Example: 2 => 02
		//if (hours   < 10) {hours   = "0"+hours;}
		//if (minutes < 10) {minutes = "0"+minutes;}
		//if (seconds < 10) {seconds = "0"+seconds;}
		//return hours+':'+minutes+':'+seconds; // Return is HH : MM : SS

		if (!value) return 0;

		let seconds = Number(value);
		var d = Math.floor(seconds / (3600 * 24));
		var h = Math.floor((seconds % (3600 * 24)) / 3600);
		var m = Math.floor((seconds % 3600) / 60);
		var s = Math.floor(seconds % 60);

		var dDisplay = d > 0 ? d + ` day${d > 1 ? 's' : ''} ` : '';
		var hDisplay = h > 0 ? h + ` hour${h > 1 ? 's' : ''} ` : '';
		var mDisplay = m > 0 ? m + ` minute${m > 1 ? 's' : ''} ` : '';
		let sDisplay = '';
		if (d == 0 && h == 0 && m == 0 && s) {
			sDisplay = s > 0 ? s + ` second${s > 1 ? 's' : ''} ` : '';
		}
		//;
		return (dDisplay + hDisplay + mDisplay + sDisplay).trim(); // + sDisplay;
	},

	relativeTimeTo(time, curr) {
		const remainingTime = dayjs(time).diff(dayjs.unix(curr), 'seconds'); // Get difference in seconds
		if (remainingTime <= 3599) {
			// Less than or equal to 1 hour
			const minutes = Math.floor(remainingTime / 60);
			const seconds = remainingTime % 60;
			return `in ${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
		}

		return dayjs().to(time);
	},

	toUpperCase(val) {
		return val.toUpperCase();
	},

	compareAddress(addr1, addr2) {
		try {
			return utils.getAddress(addr1) === utils.getAddress(addr2);
		} catch (error) {
			return false;
		}
	},

	formatUnits(val, decimals = 18, fixed = 0) {
		if (val === null || val === undefined) return '--';
		if (typeof val === 'string') val = BigInt(parseInt(val));
		//BigInt.isBigNumber
		//if (!BigNumber.isBigNumber(val)) return '--';

		let n = parseFloat(utils.formatUnits(val, decimals)).toFixed(fixed);
		return n;
		//if (n.match(/\./)) n = n.replace(/\.?0+$/, '');
		n = n.slice(0, n.indexOf('.') + fixed + 1);
		return this.numberWithCommas(n, fixed); //.replace(/\.0+$/,'');
	},

	weiToBn(val) {
		if (val === null || val === undefined) return null;
		if (typeof val === 'string') return BigNumber.from(val);
		return null;
	},

	anyBNValue(val) {
		if (val === null || val === undefined) return '--';
		if (typeof val === 'string') return val;
		if (!BigNumber.isBigNumber(val)) return '--';
		return val.toString();
	},

	numberWithCommas(x, fixed) {
		if (x === undefined || x === null || x === '--') return '--';
		if (x === '--' || x === 'ERROR') return x;
		return parseFloat(parseFloat(x).toFixed(fixed));
		//console.log(parseFloat(parseFloat(x).toFixed(fixed)))
		var parts = parseFloat(parseFloat(x).toFixed(fixed)).toLocaleString('fullwide', { useGrouping: false }).split('.');

		parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
		return parts.join('.');
	},

	abbrNum(number, decPlaces = 0) {
		if (number === undefined || number === null) return '--';
		if (number === '--' || number === 'ERROR') return number;
		// 2 decimal places => 100, 3 => 1000, etc
		decPlaces = Math.pow(10, decPlaces);
		// Enumerate number abbreviations
		var abbrev = ['k', 'm', 'b', 't'];
		// Go through the array backwards, so we do the largest first
		for (var i = abbrev.length - 1; i >= 0; i--) {
			// Convert array index to "1000", "1000000", etc
			var size = Math.pow(10, (i + 1) * 3);
			// If the number is bigger or equal do the abbreviation
			if (size <= number) {
				// Here, we multiply by decPlaces, round, and then divide by decPlaces.
				// This gives us nice rounding to a particular decimal place.
				number = Math.round((number * decPlaces) / size) / decPlaces;
				// Handle special case where we round up to the next abbreviation
				if (number == 1000 && i < abbrev.length - 1) {
					number = 1;
					i++;
				}
				// Add the letter for the abbreviation
				number += abbrev[i];
				// We are done... stop
				break;
			}
		}
		return number;
	},
};
