<template> 
    <!-- Header -->                                
    <div class="d-flex align-items-center justify-content-center text-center mb-3 fs-3">                    
        {{ data.title }}      
    </div>

    <div class="border-bottom opacity-75 my-3"></div>

    <div class="mb-3 text-center" v-html="data.content">
        
    </div>

    <div class="border-bottom opacity-75 my-2"></div>

    <div class="d-flex justify-content-center mt-3">    
        <button type="button" class="btn btn-outline-dark" @click="cancel()" >
            <trn k="tx_confirm.cancel" >
                Cancel
            </trn>
        </button>
        <button type="button" class="btn btn-dark ms-2 px-4" @click="confirm()" >
            <trn k="tx_confirm.ok" >
                Continue
            </trn>
        </button>
    </div>  
</template>

<script setup>
	import { inject } from 'vue';

    const $mitt = inject('$mitt')

    const { data } = defineProps({
        data: { type: Object, required: true },
    })
        
    function cancel() {                 
        $mitt.emit('swal::close', false) 
    }
       
    function confirm() {                 
        $mitt.emit('swal::close', 'ok') 
    }
</script>
