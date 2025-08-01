import { defineStore } from 'pinia'

export const useBreakpoint = defineStore('breakpoint', {
	state: () => ({ 
        width: 0,
		breakPoints: {
            xs: 0,
            sm: 690,
            md: 768,
            lg: 992,
            xl: 1200,
            xxl: 1400
        },
	}),
	getters: {
        list(state) { return Object.keys(state.breakPoints) },
        currentIndex() { return this.list.findIndex(e => e === this.current) },
		current(state) {
            let currentBP            
            this.list.forEach(k => {
                if (state.width >= state.breakPoints[k]) {
                    currentBP = k
                }                
            })
            return currentBP
        },        
        gt() { return function(bp) {
            return this.bpIndex(bp) < this.currentIndex
        }},
        gte() { return function(bp) {
            return this.bpIndex(bp) <= this.currentIndex
        }},        
        lt() { return function(bp) {
            return this.bpIndex(bp) > this.currentIndex
        }},
        lte() { return function(bp) {
            return this.bpIndex(bp) >= this.currentIndex
        }},
        btw() { return function(bp1, bp2) {
            return this.bpIndex(bp1) < this.currentIndex && this.bpIndex(bp2) > this.currentIndex
        }},
        btwe() { return function(bp1, bp2) {
            return this.bpIndex(bp1) <= this.currentIndex && this.bpIndex(bp2) >= this.currentIndex
        }}, 
        eq() { return function(bp) {
            return this.bpIndex(bp) == this.currentIndex 
        }},  
        ne() { return function(bp) {
            return this.bpIndex(bp) != this.currentIndex 
        }},
        in() { return function(bpList) {
            return !!bpList.find(bp => this.bpIndex(bp) == this.currentIndex) 
        }},   
        nin() { return function(bpList) {
            return !bpList.find(bp => this.bpIndex(bp) == this.currentIndex) 
        }},    
	},
	actions: {
        bpIndex(bp) {
            return this.list.findIndex(e => e === bp)
        },
        init() {
            this.width = window.innerWidth
            window.addEventListener("resize", this.setWidth);
        },
        setWidth(event) {
            this.width = event.target.innerWidth;     
        }		      		
	}
})
