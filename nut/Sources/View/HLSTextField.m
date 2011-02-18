//
//  HLSTextField.m
//  nut
//
//  Created by Samuel Défago on 10/12/10.
//  Copyright 2010 Hortis. All rights reserved.
//

#import "HLSTextField.h"

#import "HLSFloat.h"
#import "HLSKeyboardInformation.h"
#import "HLSLogger.h"

// The minimal distance to be kept between the active text field and the keyboard
const CGFloat kTextFieldMinDistanceFromKeyboard = 30.f;

@interface HLSTextField ()

/**
 * The first scroll view up the view hierarchy is the one whose content offset is adjusted to keep the field visible
 *
 * Remark:
 * To keep a field visible, some implementations directly move the parent view (not the content offset of a scroll view).
 * This is only possible in a view controller implementation, where the UI appearance is precisely known (since managed 
 * by the view controller). Here, to get the same behavior at the UIView level (where we cannot know how the UI is
 * supposed to look, which fields are grouped, etc.), we cannot simply adjust the parent view frame. What we need is a
 * way to identify which view up the caller hierarchy can be adjusted when some of its content needs to stay visible. 
 * The most natural such object is a scroll view, namely the first one encountered when climbing up the view hierarchy.
 */
@property (nonatomic, assign) UIScrollView *scrollView;

- (void)makeVisible;
- (void)restore;

- (void)keyboardWillShow:(NSNotification *)notification;
- (void)keyboardWillHide:(NSNotification *)notification;

@end

@implementation HLSTextField

#pragma mark Object creation and destruction

- (id)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        
    }
    return self;
}

- (void)dealloc
{
    self.scrollView = nil;
    [super dealloc];
}

#pragma mark Accessors and mutators

@synthesize scrollView = m_scrollView;

#pragma mark Focus events

- (BOOL)becomeFirstResponder
{
    if (! [super becomeFirstResponder]) {
        return NO;
    }
    
    // Listen to keyboard appearance notifications. If any occurs while the text field is first responder, this means that
    // the device has been rotated and that the keyboard for the new orientation is about to be displayed
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(keyboardWillShow:) 
                                                 name:UIKeyboardWillShowNotification 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(keyboardWillHide:) 
                                                 name:UIKeyboardWillHideNotification 
                                               object:nil];
    
    [self makeVisible];
    return YES;
}

- (BOOL)resignFirstResponder
{
    if (! [super resignFirstResponder]) {
        return NO;
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [self restore];
    return YES;
}

#pragma mark Locating a scroll view and using it to keep the text field visible

- (void)makeVisible
{
    // Look for the first encountered scroll view up the view hierarchy
    UIView *parentView = [self superview];
    while (parentView) {
        if ([parentView isKindOfClass:[UIScrollView class]]) {            
            self.scrollView = (UIScrollView *)parentView;
            
            // Text field frame in scroll view coordinate system;
            CGRect frameInScrollView = [self convertRect:self.bounds toView:self.scrollView];
            
            // Get the keyboard frame (should be available)
            HLSKeyboardInformation *keyboardInformation = [HLSKeyboardInformation keyboardInformation];
            if (keyboardInformation) {
                // Work in the scroll view coordinate system
                // Remark: Initially, I intended to work in the window coordinate system, but this is a bad idea
                //         (the window coordinate system is in portrait mode, and this does not make conversion
                //         of coordinates easy for views displayed in landscape mode). But we can pick any 
                //         coordinate system (as long as all coordinates are converted back to it, of course),
                //         and the most natural is the scroll view coordinate system
                
                // Get the area covered by the keyboard in the scroll view coordinate system
                CGRect keyboardFrameInScrollView = [self.scrollView convertRect:keyboardInformation.endFrame fromView:nil];
                
                // Find if the text field is covered by the keyboard, and scroll again if this is the case
                //
                //                                                  Scroll view
                //                                     +    +--------------------------+    +
                //                                     |    |                          |    |
                //      a (text field origin in scroll |    |                          |    | b (keyboard origin in scroll)
                //         view coordinate system)     |    |                          |    |    view coordinate system)
                //                                     |    |                          |    |
                //                                     |    |                          |    |
                //                                     +    |   +---------+            |    |        +
                //                                          |   |  Field  |            |    |        |   f (text field height)
                //                                          |   +---------+            |    |        +
                //                                          |                          |    |
                //                                          |                          |    |
                //                                          +--------------------------+    +
                //                                          |                          |
                //                                          |         Keyboard         |
                //                                          |                          |
                //                                          +--------------------------+
                //
                //
                // Let d be the minimal distance to be kept between text field and keyboard. Then, in order for the field to
                // be visible, we must have:
                //   a + f + d < b
                // or
                //   a + f + d - b < 0
                // Let delta := a + f + d - b, then we must shift the scroll view content offset if this condition is not satisfied,
                // i.e. when
                //   delta >= 0
                // The shift to apply is just delta
                CGFloat deltaY = frameInScrollView.origin.y + frameInScrollView.size.height + kTextFieldMinDistanceFromKeyboard - keyboardFrameInScrollView.origin.y;
                if (floatge(deltaY, 0)) {
                    // No animation here, otherwise incorrect behavior (may offsetting too much when tabbing between fields)
                    m_deltaY = deltaY;
                    CGPoint scrollViewOffset = self.scrollView.contentOffset;
                    [self.scrollView setContentOffset:CGPointMake(scrollViewOffset.x,
                                                                  scrollViewOffset.y + m_deltaY) 
                                             animated:NO];
                }
                else {
                    m_deltaY = 0.f;
                }
            }
            else {
                logger_warn(@"Keyboard information not available. Text field behavior might be incorrect");
                m_deltaY = 0.f;
            }
            break;
        }
        parentView = [parentView superview];
    }
}

/**
 * Restore the scroll view offset. Must be called for the same orientation as when the makeVisible method was called,
 * otherwise the behavior is undefined
 */
- (void)restore
{
    // No animation, otherwise incorrect behavior (may offsetting too much when tabbing between fields)
    CGPoint scrollViewOffset = self.scrollView.contentOffset;
    [self.scrollView setContentOffset:CGPointMake(scrollViewOffset.x, 
                                                  scrollViewOffset.y - m_deltaY) 
                             animated:NO];
    
    // No more scroll view moved
    self.scrollView = nil;
}

#pragma mark Notification callbacks

/**
 * Extremely important: When rotating the interface with the keyboard enabled, the willShow event is fired after the new
 * orientation has been installed, i.e. coordinates are relative to the new orientation
 */
- (void)keyboardWillShow:(NSNotification *)notification
{
    [self makeVisible];
}

/**
 * Extremely important: When rotating the interface with the keyboard enabled, the willHide event is fired before the new
 * orientation has been installed, i.e. coordinates are relative to the old orientation
 */
- (void)keyboardWillHide:(NSNotification *)notification
{
    [self restore];
}

@end
