// Accessible dialog composed in the shadcn/ui pattern (MIT).
import * as DialogPrimitive from '@radix-ui/react-dialog';
import { X } from 'lucide-react';
import type { ReactNode } from 'react';
export function Dialog({
  open,
  onOpenChange,
  title,
  description,
  children,
  closeLabel,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description?: string;
  children: ReactNode;
  closeLabel: string;
}) {
  return (
    <DialogPrimitive.Root open={open} onOpenChange={onOpenChange}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="dialog-overlay" />
        <DialogPrimitive.Content
          className="dialog-content"
          aria-describedby={description ? 'dialog-description' : undefined}
        >
          <DialogPrimitive.Title className="dialog-title">{title}</DialogPrimitive.Title>
          {description && (
            <DialogPrimitive.Description id="dialog-description" className="dialog-description">
              {description}
            </DialogPrimitive.Description>
          )}
          {children}
          <DialogPrimitive.Close className="dialog-close" aria-label={closeLabel}>
            <X size={18} />
          </DialogPrimitive.Close>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}
