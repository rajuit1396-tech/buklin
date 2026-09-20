import {z} from 'zod';
export const machineTypes = ['5-finger excavator grapple','Pickup van','Big truck'];
export const accountFields = z.object({
  name:z.string().trim().min(2).max(100),
  phone:z.string().trim().regex(/^\+?[0-9]{7,15}$/),
  username:z.string().trim().toLowerCase().regex(/^[a-z0-9_]{3,40}$/),
  password:z.string().min(10).max(128),
});
export const accountLocation = z.object({
  site_lat:z.number().min(-90).max(90),
  site_lng:z.number().min(-180).max(180),
  site_address:z.string().trim().min(5).max(300),
});
export const adminAccount = accountFields.extend({
  ...accountLocation.partial().shape,
  role:z.enum(['customer','operator']),
  service:z.enum(machineTypes).nullable().optional(),
  store_number:z.string().regex(/^[0-9]{3}$/).nullable().optional(),
}).superRefine((value,context)=>{
  if(value.role==='customer') for(const field of ['site_lat','site_lng','site_address']) {
    if(value[field] === undefined) context.addIssue({code:'custom',path:[field],message:'Choose the customer location'});
  }
  if(value.role==='customer' && !value.store_number) context.addIssue({code:'custom',path:['store_number'],message:'Enter a three-digit store number'});
  if(value.role==='operator' && !value.service) context.addIssue({code:'custom',path:['service'],message:'Select a machine'});
  if(value.role==='customer' && value.service) context.addIssue({code:'custom',path:['service'],message:'Customers have no machine'});
});
