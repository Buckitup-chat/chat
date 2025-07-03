import Swal from 'sweetalert2'

const $swal = Swal.mixin({
    buttonsStyling: false,
    position: 'top',    
    customClass: {
        //popup: '_swal2_popup',
        confirmButton: 'btn btn-primary px-4 mx-2 mb-2',
        denyButton: 'btn btn-outline-primary px-4 mx-2 mb-2',
        cancelButton: 'btn btn-outline-primary px-4 mx-2 mb-2',
        footer: 'text-break',
        //icon: '_swal_icon',
        //title:  '_swal_title',
        //htmlContainer: '_swal_html_container',
        //closeButton: '_swal_close_button',
        //closeIcon: '_i_times',
    },
    showConfirmButton: false,
    showCloseButton: true,
    reverseButtons: true,
    focusConfirm: false, // Prevent focus on confirm button
    focusDeny: false,     // Prevent focus on deny button if shown
    returnFocus: false,
    //iconHtml: '<i>fff</i>'

    //toast: true,
    //position: 'top-end',
    //showConfirmButton: false,
    //timer: 3000,
    //timerProgressBar: true,
    //didOpen: (toast) => {
    //    toast.addEventListener('mouseenter', Swal.stopTimer)
    //    toast.addEventListener('mouseleave', Swal.resumeTimer)
    //}
})


export default $swal 