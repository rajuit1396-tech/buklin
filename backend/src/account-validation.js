import {z} from 'zod';
export const machineTypes = ['5-finger excavator grapple','Pickup van','Big truck'];
export const accountFields = z.object({
  name:z.string().trim().min(2).max(100),
  phone:z.string().trim().regex(/^\+?[0-9]{7,15}$/),
  username:z.string().trim().toLowerCase().regex(/^[a-z0-9_]{3,40}$/),
  password:z.string().min(10).max(128),
});
export const adminAccount = accountFields.extend({
  role:z.enum(['customer','operator']),
  service:z.enum(machineTypes).nullable().optional(),
  store_number:z.string().regex(/^[0-9]{3}$/).nullable().optional(),
}).superRefine((value,context)=>{
  if(value.role==='customer' && !value.store_number) context.addIssue({code:'custom',path:['store_number'],message:'Enter a three-digit store number'});
  if(value.role==='operator' && !value.service) context.addIssue({code:'custom',path:['service'],message:'Select a machine'});
  if(value.role==='customer' && value.service) context.addIssue({code:'custom',path:['service'],message:'Customers have no machine'});
});
