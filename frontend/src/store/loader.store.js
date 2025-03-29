import { defineStore } from "pinia";
import { ref } from 'vue';

export const useLoader = defineStore('loader', () => {    
   
    const enabled = ref(false)        
    const show = () => {
        enabled.value = true                       
    }
    const hide = () => {  
        enabled.value = false                 
    }    
    return {
        enabled,
        show, 
        hide,         
    }
})
